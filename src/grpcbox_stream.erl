-module(grpcbox_stream).

-include_lib("chatterbox/include/http2.hrl").
-include_lib("kernel/include/logger.hrl").
-include("grpcbox.hrl").

-behaviour(h2_stream).

-export([
         send/3,
         send_headers/2,
         update_headers/2,
         add_trailers/2,
         set_trailers/2,
         update_trailers/2,
         code_to_status/1,
         error/2,
         ctx/1,
         ctx/2,
         end_stream/1,
         handle_streams/2,
         handle_call/2,
         handle_info/2]).

-export([init/3,
         on_receive_request_headers/2,
         on_send_push_promise/2,
         on_receive_request_data/2,
         on_request_end_stream/1]).

%% state getters and setters
-export([stream_handler_state/1,
         stream_handler_state/2,
         stream_req_headers/1
]).

%% state getters and setters
-export([stream_handler_state/1,
         stream_handler_state/2,
         stream_req_headers/1
]).

-export_type([t/0,
              grpc_status/0,
              grpc_status_message/0,
              grpc_error/0,
              grpc_error_response/0,
              grpc_error_data/0,
              grpc_extended_error_response/0]).

-record(state, {handler                 :: pid(),
                stream_handler_state    :: any(),
                socket,
                auth_fun,
                buffer                  :: binary(),
                ctx                     :: ctx:ctx(),
                services_table          :: ets:tid(),
                req_headers=[]          :: list(),
                full_method             :: binary() | undefined,
                connection_pid          :: pid(),
                request_encoding        :: gzip | identity | undefined,
                response_encoding       :: gzip | identity | undefined,
                content_type            :: proto | json | undefined,
                resp_headers=[]         :: list(),
                resp_trailers=[]        :: list(),
                headers_sent=false      :: boolean(),
                trailers_sent=false     :: boolean(),
                unary_interceptor       :: fun() | undefined,
                stream_interceptor      :: fun() | undefined,
                stream_id               :: stream_id(),
                method                  :: #method{} | undefined,
                stats_handler           :: module() | undefined,
                stats                   :: term() | undefined}).

-type t() :: #state{}.

-type grpc_status_message() :: unicode:chardata().
-type grpc_status() :: 0..16.
-type grpc_error() :: {grpc_status(), grpc_status_message()}.
-type grpc_error_response() :: {grpc_error, grpc_error()}.
-type grpc_error_data() :: #{
    status := grpc_status(),
    message := grpc_status_message(),
    trailers => map()
}.
-type grpc_extended_error_response() :: {grpc_extended_error, grpc_error_data()}.

-spec stream_handler_state(t()) -> any().
stream_handler_state(#state{stream_handler_state = StreamHandlerState}) ->
    StreamHandlerState.
-spec stream_handler_state(t(), any()) -> any().
stream_handler_state(State, NewStreamHandlerState) ->
    State#state{stream_handler_state = NewStreamHandlerState}.

-spec stream_req_headers(t()) -> list().
stream_req_headers(#state{req_headers = ReqHeaders}) ->
    ReqHeaders.

init(ConnPid, StreamId, [Socket, ServicesTable, AuthFun, UnaryInterceptor,
                         StreamInterceptor, StatsHandler]) ->
    process_flag(trap_exit, true),
    State = #state{connection_pid=ConnPid,
                   stream_id=StreamId,
                   services_table=ServicesTable,
                   buffer = <<>>,
                   auth_fun=AuthFun,
                   unary_interceptor=UnaryInterceptor,
                   stream_interceptor=StreamInterceptor,
                   socket=Socket,
                   handler=self(),
                   stats_handler=StatsHandler},
    {ok, State}.

on_receive_request_headers(Headers, State=#state{ctx=_Ctx}) ->
    Metadata = grpcbox_utils:headers_to_metadata(Headers),
    Ctx = case parse_options(<<"grpc-timeout">>, Headers) of
               infinity ->
                   grpcbox_metadata:new_incoming_ctx(Metadata);
               D ->
                   ctx:with_deadline_after(grpcbox_metadata:new_incoming_ctx(Metadata), D, nanosecond)
           end,

    FullPath = proplists:get_value(<<":path">>, Headers),
    %% wait to rpc_begin here since we need to know the method
    Ctx1 = ctx:with_value(Ctx, grpc_server_method, FullPath),
    State1=#state{ctx=Ctx2} = stats_handler(Ctx1, rpc_begin, {}, State#state{full_method=FullPath}),

    RequestEncoding = parse_options(<<"grpc-encoding">>, Headers),
    ResponseEncoding = parse_options(<<"grpc-accept-encoding">>, Headers),
    ContentType = parse_options(<<"content-type">>, Headers),

    RespHeaders = [{<<":status">>, <<"200">>},
                   {<<"user-agent">>, <<"grpc-erlang/0.1.0">>},
                   {<<"content-type">>, content_type(ContentType)}
                   | response_encoding(ResponseEncoding)],

    handle_service_lookup(Ctx2, string:lexemes(FullPath, "/"),
                          State1#state{resp_headers=RespHeaders,
                                       req_headers=Headers,
                                       request_encoding=RequestEncoding,
                                       response_encoding=ResponseEncoding,
                                       content_type=ContentType}).

handle_service_lookup(Ctx, [Service, Method], State=#state{services_table=ServicesTable}) ->
    case ets:lookup(ServicesTable, {Service, Method}) of
        [M=#method{}] ->
            State1 = State#state{ctx=Ctx,
                                 method=M},
            handle_auth(Ctx, State1);
        _ ->
            end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"Method not found on server">>, State)
    end;
handle_service_lookup(_, _, State) ->
    State1 = State#state{resp_headers=[{<<":status">>, <<"200">>},
                                       {<<"user-agent">>, <<"grpc-erlang/0.1.0">>}]},
    end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"failed parsing path">>, State1),
    {ok, State1}.

handle_auth(_Ctx, State=#state{auth_fun=AuthFun,
                               socket=Socket,
                               method=#method{module=Module,
                                              function=Function}}) ->
    case authenticate(sock:peercert(Socket), AuthFun) of
        {true, _Identity} ->
            State0 = maybe_init_handler_state(Module, Function, State),
            %% send resp headers after verifying client request
            %% some clients require grpc headers to be sent within a defined time period
            %% otherwise they assume the request has failed and bail out
            %% previously server would only return headers upon first data msg send
            %% this can cause issues with streaming connections, for example
            %% if a client connects and there are no data msgs ready to be sent back to them
            %% TODO: check what grpc spec says about this
            %% TODO: sending the headers here negates update_headers/2 usefullness ? somewhere better to send em?
            State1 = send_headers(State0),
            {ok, State1};
        _ ->
            end_stream(?GRPC_STATUS_UNAUTHENTICATED, <<"">>, State)
    end.

authenticate(_, undefined) ->
    {true, undefined};
authenticate({ok, Cert}, Fun) ->
    Fun(Cert);
authenticate(_, _) ->
    false.

handle_streams(Ref, State=#state{full_method=FullMethod,
                                 stream_interceptor=StreamInterceptor,
                                 method=#method{module=Module,
                                                function=Function,
                                                output={_, false}}}) ->
    case (case StreamInterceptor of
              undefined -> Module:Function(Ref, State);
              _ ->
                  ServerInfo = #{full_method => FullMethod,
                                 service => Module,
                                 input_stream => true,
                                 output_stream => false},
                  StreamInterceptor(Ref, State, ServerInfo, fun Module:Function/2)
          end) of
        {ok, State1} ->
            State1;
        {ok, Response, State1} ->
            State2 = send(false, Response, State1),
            {ok, State3} = end_stream(State2),
            _ = stop_stream(?STREAM_CLOSED, State3),
            {ok, State3};
        {stop, State1} ->
            {ok, State2} = end_stream(State1),
            _ = stop_stream(?STREAM_CLOSED, State2),
            {ok, State2};
        {stop, Response, State1} ->
            State2 = send(false, Response, State1),
            {ok, State3} = end_stream(State2),
            _ = stop_stream(?STREAM_CLOSED, State3)
            {ok, State3};
        E={grpc_error, _} ->
            throw(E);
        E={grpc_extended_error, _} ->
            throw(E)
    end;

handle_streams(Ref, State=#state{full_method=FullMethod,
                                 stream_interceptor=StreamInterceptor,
                                 method=#method{module=Module,
                                                function=Function,
                                                output={_, true}}}) ->
    case (case StreamInterceptor of
              undefined -> Module:Function(Ref, State);
              _ ->
                  ServerInfo = #{full_method => FullMethod,
                                 service => Module,
                                 input_stream => true,
                                 output_stream => true},
                  StreamInterceptor(Ref, State, ServerInfo, fun Module:Function/2)
          end) of
        {ok, State1} ->
            State1;
        {ok, Response, State1} ->
            send(false, Response, State1);
        {stop, State1} ->
            {ok, State2} = end_stream(State1),
            _ = stop_stream(?STREAM_CLOSED, State2),
            {ok, State2};
        {stop, Response, State1} ->
            State2 = send(false, Response, State1),
            {ok, State3} = end_stream(State2),
            _ = stop_stream(?STREAM_CLOSED, State3),
            {ok, State3};
        {grpc_error, {Status, Message}} ->
            {ok, State1} = end_stream(Status, Message, State),
            _ = stop_stream(?STREAM_CLOSED, State1),
            {ok, State1};
        {grpc_extended_error, #{status := Status, message := Message} = ErrorData} ->
            State1 = add_trailers_from_error_data(ErrorData, State),
            {ok, State2} = end_stream(Status, Message, State1),
            _ = stop_stream(?STREAM_CLOSED, State2),
            {ok, State2}
    end.

on_send_push_promise(_, State) ->
    {ok, State}.

ctx_with_stream(Ctx, Stream) ->
    ctx:set(Ctx, ctx_stream_key, Stream).

from_ctx(Ctx) ->
    ctx:get(Ctx, ctx_stream_key).

on_receive_request_data(_, State=#state{method=undefined}) ->
    {ok, State};
on_receive_request_data(Bin, State=#state{request_encoding=Encoding,
                                  buffer=Buffer}) ->
    try
        {NewBuffer, Messages} = grpcbox_frame:split(<<Buffer/binary, Bin/binary>>, Encoding),
        State1 = lists:foldl(fun(EncodedMessage, StateAcc=#state{}) ->
                                     StateAcc1 = handle_message(EncodedMessage, StateAcc),
                                     StateAcc1
                             end, State, Messages),
        {ok, State1#state{buffer=NewBuffer}}
    catch
        throw:{grpc_error, {Status, Message}} ->
            end_stream(Status, Message, State);
        throw:{grpc_extended_error, #{status := Status, message := Message} = ErrorData} ->
            State2 = add_trailers_from_error_data(ErrorData, State),
            end_stream(Status, Message, State2);
        C:E:S ->
            ?LOG_INFO("crash: class=~p exception=~p stacktrace=~p", [C, E, S]),
            end_stream(?GRPC_STATUS_UNKNOWN, <<>>, State)
    end.

handle_message(EncodedMessage, State=#state{ctx=Ctx,
                                            method=#method{proto=Proto,
                                                           input={Input, InputStream},
                                                           output={_Output, OutputStream}}}) ->
    try Proto:decode_msg(EncodedMessage, Input) of
        Message ->
            State1=#state{ctx=Ctx1} =
                stats_handler(Ctx, in_payload, #{uncompressed_size => erlang:external_size(Message),
                                                 compressed_size => size(EncodedMessage)}, State),
            case {InputStream, OutputStream} of
                {false, false} ->
                    handle_unary(Ctx1, Message, State1);
                {_, _} ->
                    handle_streams(Message, State1#state{handler=self()})
            end
    catch
        error:{gpb_error, _} ->
            ?THROW(?GRPC_STATUS_INTERNAL, <<"Error parsing request protocol buffer">>)
    end.

handle_unary(Ctx, Message, State=#state{unary_interceptor=UnaryInterceptor,
                                        full_method=FullMethod,
                                        method=#method{module=Module,
                                                       function=Function,
                                                       proto=_Proto,
                                                       input={_Input, _InputStream},
                                                       output={_Output, _OutputStream}}}) ->
    Ctx1 = ctx_with_stream(Ctx, State),
    case (case UnaryInterceptor of
              undefined -> Module:Function(Ctx1, Message);
              _ ->
                  ServerInfo = #{full_method => FullMethod,
                                 service => Module},
                  UnaryInterceptor(Ctx1, Message, ServerInfo,
                                   fun Module:Function/2)
          end) of
        {ok, Response, Ctx2} ->
            State1 = from_ctx(Ctx2),
            send(false, Response, State1);
        E={grpc_error, _} ->
            throw(E);
        E={grpc_extended_error, _} ->
            throw(E)
    end.

on_end_stream(State) ->
    on_end_stream_(State),
    {ok, State}.

on_end_stream_(State=#state{method=#method{input={_Input, true},
                                     output={_Output, false}}}) ->
    handle_streams(eos, State);
on_end_stream_(State = #state{method=#method{input={_Input, true},
                                     output={_Output, true}}}) ->
    handle_streams(eos, State);
on_end_stream_(#state{method=#method{input={_Input, false},
                                     output={_Output, true}}}) ->
    ok;
on_request_end_stream_(State=#state{method=#method{output={_Output, false}}}) ->
    end_stream(State);
on_request_end_stream_(State) ->
    end_stream(State).

%% Internal

stats_handler(Ctx, _, _, State=#state{stats_handler=undefined}) ->
    State#state{ctx=Ctx};
stats_handler(Ctx, Event, Stats, State=#state{stats_handler=StatsHandler,
                                              stats=StatsState}) ->
    {Ctx1, StatsState1} = StatsHandler:handle(Ctx, server, Event, Stats, StatsState),
    State#state{ctx=Ctx1,
                stats=StatsState1}.

end_stream(State) ->
    end_stream(?GRPC_STATUS_OK, <<>>, State).

end_stream(Status, Message, State=#state{headers_sent=false}) ->
    end_stream(Status, Message, send_headers(State));
end_stream(_Status, _Message, State=#state{trailers_sent=true}) ->
    {ok, State};
end_stream(Status, Message, State=#state{connection_pid=ConnPid,
                                         stream_id=StreamId,
                                         ctx=Ctx,
                                         resp_trailers=Trailers}) ->
    EncodedTrailers = grpcbox_utils:encode_headers(Trailers),
    h2_connection:send_trailers(ConnPid, StreamId, [{<<"grpc-status">>, Status},
                                                    {<<"grpc-message">>, Message} | EncodedTrailers],
                                [{send_end_stream, true}]),
    Ctx1 = ctx:with_value(Ctx, grpc_server_status, grpcbox_utils:status_to_string(Status)),
    State1 = stats_handler(Ctx1, rpc_end, {}, State),
    {ok, State1#state{trailers_sent=true}}.

set_trailers(Ctx, Trailers) ->
    State = from_ctx(Ctx),
    ctx_with_stream(Ctx, State#state{resp_trailers=maps:to_list(Trailers)}).

send_headers(State) ->
    send_headers([], State).

send_headers(Ctx, Headers) when is_map(Headers) ->
    State = from_ctx(Ctx),
    send_headers(maps:to_list(maybe_encode_headers(Headers)), State);

send_headers(_Metadata, State=#state{headers_sent=true}) ->
    State;
send_headers(Metadata, State=#state{connection_pid=ConnPid,
                                    stream_id=StreamId,
                                    resp_headers=Headers,
                                    headers_sent=false}) ->
    MdHeaders = grpcbox_utils:encode_headers(Metadata),
    h2_connection:send_headers(ConnPid, StreamId, Headers ++ MdHeaders, [{send_end_stream, false}]),
    State#state{headers_sent=true}.

code_to_status(0) -> ?GRPC_STATUS_OK;
code_to_status(1) -> ?GRPC_STATUS_CANCELLED;
code_to_status(2) -> ?GRPC_STATUS_UNKNOWN;
code_to_status(3) -> ?GRPC_STATUS_INVALID_ARGUMENT;
code_to_status(4) -> ?GRPC_STATUS_DEADLINE_EXCEEDED;
code_to_status(5) -> ?GRPC_STATUS_NOT_FOUND;
code_to_status(6) -> ?GRPC_STATUS_ALREADY_EXISTS;
code_to_status(7) -> ?GRPC_STATUS_PERMISSION_DENIED;
code_to_status(8) -> ?GRPC_STATUS_RESOURCE_EXHAUSTED;
code_to_status(9) -> ?GRPC_STATUS_FAILED_PRECONDITION;
code_to_status(10) -> ?GRPC_STATUS_ABORTED;
code_to_status(11) -> ?GRPC_STATUS_OUT_OF_RANGE;
code_to_status(12) -> ?GRPC_STATUS_UNIMPLEMENTED;
code_to_status(13) -> ?GRPC_STATUS_INTERNAL;
code_to_status(14) -> ?GRPC_STATUS_UNAVAILABLE;
code_to_status(15) -> ?GRPC_STATUS_DATA_LOSS;
code_to_status(16) -> ?GRPC_STATUS_UNAUTHENTICATED.

error(Status, Message) ->
    exit(?GRPC_ERROR(Status, Message)).

ctx(#state{handler=Pid}) ->
    h2_stream:call(Pid, ctx).

ctx(#state{handler=Pid}, Ctx) ->
    h2_stream:call(Pid, {ctx, Ctx}).

handle_call(ctx, State=#state{ctx=Ctx}) ->
    {ok, Ctx, State};
handle_call({ctx, Ctx}, State) ->
    {ok, ok, State#state{ctx=Ctx}}.

handle_info(Msg, State=#state{method=#method{module=Module, function=Function}}) ->
    %% if the handler module exports handle_info/3, then use that
    %% the 3 version passes the invoked RPC which can be used
    %% by the handler to accommodate any function specific handling
    %% really this is a bespoke use case
    %% fall back to handle_info/2 if the /3 is not exported
    case erlang:function_exported(Module, handle_info, 3) of
        true -> Module:handle_info(Function, Msg, State);
        false ->
            case erlang:function_exported(Module, handle_info, 2) of
                true -> Module:handle_info(Msg, State);
                false ->
                    State
            end
    end.

add_trailers(Ctx, Trailers=#{}) ->
    State=#state{resp_trailers=RespTrailers} = from_ctx(Ctx),
    ctx_with_stream(Ctx, State#state{resp_trailers=maps:to_list(Trailers) ++ RespTrailers}).

update_headers(Headers, State=#state{resp_headers=RespHeaders}) ->
    State#state{resp_headers=RespHeaders ++ Headers}.

update_trailers(Trailers, State=#state{resp_trailers=RespTrailers}) ->
    State#state{resp_trailers=RespTrailers ++ Trailers}.

send(End, Message, State=#state{headers_sent=false}) ->
    State1 = send_headers(State),
    send(End, Message, State1);
send(End, Message, State=#state{ctx=Ctx,
                                connection_pid=ConnPid,
                                stream_id=StreamId,
                                response_encoding=Encoding,
                                method=#method{proto=Proto,
                                               input={_Input, _},
                                               output={Output, _}}}) ->
    BodyToSend = Proto:encode_msg(Message, Output),
    OutFrame = grpcbox_frame:encode(Encoding, BodyToSend),
    ok = h2_connection:send_body(ConnPid, StreamId, OutFrame, [{send_end_stream, End}]),
    stats_handler(Ctx, out_payload, #{uncompressed_size => erlang:external_size(Message),
                                      compressed_size => size(BodyToSend)}, State).

response_encoding(gzip) ->
    [{<<"grpc-encoding">>, <<"gzip">>}];
response_encoding(snappy) ->
    [{<<"grpc-encoding">>, <<"snappy">>}];
response_encoding(deflate) ->
    [{<<"grpc-encoding">>, <<"deflate">>}];
response_encoding(identity) ->
    [{<<"grpc-encoding">>, <<"identity">>}].

content_type(json) ->
    <<"application/grpc+json">>;
content_type(_) ->
    <<"application/grpc+proto">>.

timeout_to_duration(T, <<"H">>) ->
    erlang:convert_time_unit(timer:hours(T), millisecond, nanosecond);
timeout_to_duration(T, <<"M">>) ->
    erlang:convert_time_unit(timer:minutes(T), millisecond, nanosecond);
timeout_to_duration(T, <<"S">>) ->
    erlang:convert_time_unit(T, second, nanosecond);
timeout_to_duration(T, <<"m">>) ->
    erlang:convert_time_unit(T, millisecond, nanosecond);
timeout_to_duration(T, <<"u">>) ->
    erlang:convert_time_unit(T, microsecond, nanosecond);
timeout_to_duration(T, <<"n">>) ->
    timer:seconds(T).

parse_options(<<"grpc-timeout">>, Headers) ->
    case proplists:get_value(<<"grpc-timeout">>, Headers, infinity) of
        infinity ->
            infinity;
        T ->
            {I, U} = string:to_integer(T),
            timeout_to_duration(I, U)
    end;
parse_options(<<"content-type">>, Headers) ->
    case proplists:get_value(<<"content-type">>, Headers, undefined) of
        undefined ->
            proto;
        <<"application/grpc">> ->
            proto;
        <<"application/grpc+proto">> ->
            proto;
        <<"application/grpc+json">> ->
            json;
        <<"application/grpc+", _>> ->
            ?THROW(?GRPC_STATUS_UNIMPLEMENTED, <<"unknown content-type">>)
    end;
parse_options(<<"grpc-encoding">>, Headers) ->
    parse_encoding(<<"grpc-encoding">>, Headers);
parse_options(<<"grpc-accept-encoding">>, Headers) ->
    parse_encoding(<<"grpc-accept-encoding">>, Headers).

parse_encoding(EncodingType, Headers) ->
    case proplists:get_value(EncodingType, Headers, undefined) of
        undefined ->
            identity;
        <<"gzip", _/binary>> ->
            gzip;
        <<"snappy", _/binary>> ->
            snappy;
        <<"deflate", _/binary>> ->
            deflate;
        <<"identity", _/binary>> ->
            identity;
        _ ->
            ?THROW(?GRPC_STATUS_UNIMPLEMENTED, <<"unknown encoding">>)
    end.

maybe_encode_headers(Headers) ->
    maps:map(fun(K, V) ->
                     maybe_encode_header_value(K, V)
             end, Headers).

maybe_encode_header_value(K, V) ->
    case binary:longest_common_suffix([K, <<"-bin">>]) == 4 of
        true ->
            base64:encode(V);
        false ->
            V
    end.

add_trailers_from_error_data(ErrorData, State) ->
    Trailers = maps:get(trailers, ErrorData, #{}),
    update_trailers(maps:to_list(Trailers), State).

maybe_init_handler_state(Module, Function, State)->
    case erlang:function_exported(Module, init, 2) of
        true -> Module:init(Function, State);
        false -> State
    end.
