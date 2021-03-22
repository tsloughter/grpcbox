-module(grpcbox_stream).

-include_lib("chatterbox/include/http2.hrl").
-include_lib("kernel/include/logger.hrl").
-include("grpcbox.hrl").

-behaviour(h2_stream).

-export([send/2,
         send/3,
         send_headers/2,
         add_headers/2,
         add_trailers/2,
         set_trailers/2,
         code_to_status/1,
         error/2,
         ctx/1,
         ctx/2,
         handle_streams/2,
         handle_call/2,
         handle_info/2]).

-export([init/3,
         on_receive_headers/2,
         on_send_push_promise/2,
         on_receive_data/2,
         on_end_stream/1]).

-export_type([t/0,
              grpc_status/0,
              grpc_status_message/0,
              grpc_error/0,
              grpc_error_response/0,
              grpc_error_data/0,
              grpc_extended_error_response/0]).

-record(state, {handler             :: pid(),
                socket,
                auth_fun,
                buffer              :: binary(),
                ctx                 :: ctx:ctx(),
                services_table      :: ets:tid(),
                req_headers=[]      :: list(),
                full_method         :: binary() | undefined,
                input_ref           :: reference() | undefined,
                callback_pid        :: pid() | undefined,
                connection_pid      :: pid(),
                request_encoding    :: gzip | identity | undefined,
                response_encoding   :: gzip | identity | undefined,
                content_type        :: proto | json | undefined,
                resp_headers=[]     :: list(),
                resp_trailers=[]    :: list(),
                headers_sent=false  :: boolean(),
                trailers_sent=false :: boolean(),
                unary_interceptor   :: fun() | undefined,
                stream_interceptor  :: fun() | undefined,
                stream_id           :: stream_id(),
                method              :: #method{} | undefined,
                stats_handler       :: module() | undefined,
                stats               :: term() | undefined}).

-type t() :: #state{}.

-type grpc_status_message() :: unicode:chardata().
-type grpc_status() :: 0..16.
-type http_status() :: integer().
-type grpc_error() :: {grpc_status(), grpc_status_message()}.
-type grpc_error_response() :: {error, grpc_error(), #{headers => map(),
                                                       trailers => #{}}} |
                               {http_error, {http_status(), unicode:chardata()}, #{headers => map(),
                                                                                   trailers => #{}}} |
                               {error, term()}.
-type grpc_error_data() :: #{
    status := grpc_status(),
    message := grpc_status_message(),
    trailers => map()
}.
-type grpc_extended_error_response() :: {grpc_extended_error, grpc_error_data()}.

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

on_receive_headers(Headers, State=#state{ctx=_Ctx}) ->
    %% proplists:get_value(<<":method">>, Headers) =:= <<"POST">>,
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
                               method=#method{input={_, InputStreaming}}}) ->
    case authenticate(sock:peercert(Socket), AuthFun) of
        {true, _Identity} ->
            case InputStreaming of
                true ->
                    Ref = make_ref(),
                    Pid = proc_lib:spawn_link(?MODULE, handle_streams,
                                              [Ref, State#state{handler=self()}]),
                    {ok, State#state{input_ref=Ref,
                                     callback_pid=Pid}};
                _ ->
                    {ok, State}
            end;
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
        {ok, Response, State2} ->
            send(Response, State2);
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
    case StreamInterceptor of
        undefined ->
            Module:Function(Ref, State);
        _ ->
            ServerInfo = #{full_method => FullMethod,
                           service => Module,
                           input_stream => true,
                           output_stream => true},
            StreamInterceptor(Ref, State, ServerInfo, fun Module:Function/2)
    end.

on_send_push_promise(_, State) ->
    {ok, State}.

ctx_with_stream(Ctx, Stream) ->
    ctx:set(Ctx, ctx_stream_key, Stream).

from_ctx(Ctx) ->
    ctx:get(Ctx, ctx_stream_key).

on_receive_data(_, State=#state{method=undefined}) ->
    {ok, State};
on_receive_data(Bin, State=#state{request_encoding=Encoding,
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

handle_message(EncodedMessage, State=#state{input_ref=Ref,
                                            ctx=Ctx,
                                            callback_pid=Pid,
                                            method=#method{proto=Proto,
                                                           input={Input, InputStream},
                                                           output={_Output, OutputStream}}}) ->
    try Proto:decode_msg(EncodedMessage, Input) of
        Message ->
            State1=#state{ctx=Ctx1} =
                stats_handler(Ctx, in_payload, #{uncompressed_size => erlang:external_size(Message),
                                                 compressed_size => size(EncodedMessage)}, State),
            case {InputStream, OutputStream} of
                {true, _} ->
                    Pid ! {Ref, Message},
                    State1;
                {false, true} ->
                    _ = proc_lib:spawn_link(?MODULE, handle_streams,
                                            [Message, State1#state{handler=self()}]),
                    State1;
                {false, false} ->
                    handle_unary(Ctx1, Message, State1)
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

on_end_stream_(#state{input_ref=Ref,
                      callback_pid=Pid,
                      method=#method{input={_Input, true},
                                     output={_Output, false}}}) ->
    Pid ! {Ref, eos};
on_end_stream_(#state{input_ref=Ref,
                      callback_pid=Pid,
                      method=#method{input={_Input, true},
                                     output={_Output, true}}}) ->
    Pid ! {Ref, eos};
on_end_stream_(#state{input_ref=_Ref,
                      callback_pid=_Pid,
                      method=#method{input={_Input, false},
                                     output={_Output, true}}}) ->
    ok;
on_end_stream_(State=#state{method=#method{output={_Output, false}}}) ->
    end_stream(State);
on_end_stream_(State) ->
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

handle_info({add_headers, Headers}, State) ->
    update_headers(Headers, State);
handle_info({add_trailers, Trailers}, State) ->
    update_trailers(Trailers, State);
handle_info({send_proto, Message}, State) ->
    send(false, Message, State);
handle_info({'EXIT', _, normal}, State) ->
    end_stream(State),
    State;
handle_info({'EXIT', _, {grpc_error, {Status, Message}}}, State) ->
    end_stream(Status, Message, State),
    State;
handle_info({'EXIT', _, {grpc_extended_error, #{status := Status, message := Message} = ErrorData}}, State) ->
    State1 = add_trailers_from_error_data(ErrorData, State),
    end_stream(Status, Message, State1),
    State1;
handle_info({'EXIT', _, _Other}, State) ->
    end_stream(?GRPC_STATUS_UNKNOWN, <<"process exited without reason">>, State),
    State;
handle_info(_, State) ->
    State.


add_headers(Headers, #state{handler=Pid}) ->
    Pid ! {add_headers, Headers}.

add_trailers(Ctx, Trailers=#{}) ->
    State=#state{resp_trailers=RespTrailers} = from_ctx(Ctx),
    ctx_with_stream(Ctx, State#state{resp_trailers=maps:to_list(Trailers) ++ RespTrailers});
add_trailers(Headers, #state{handler=Pid}) ->
    Pid ! {add_trailers, Headers}.

update_headers(Headers, State=#state{resp_headers=RespHeaders}) ->
    State#state{resp_headers=RespHeaders ++ Headers}.

update_trailers(Trailers, State=#state{resp_trailers=RespTrailers}) ->
    State#state{resp_trailers=RespTrailers ++ Trailers}.

send(Message, #state{handler=Pid}) ->
    Pid ! {send_proto, Message}.

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
