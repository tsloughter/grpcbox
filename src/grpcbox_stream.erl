-module(grpcbox_stream).

-include_lib("kernel/include/logger.hrl").
-include_lib("grpcbox/include/grpcbox.hrl").

-behaviour(gen_server).

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
         handle_streams/2]).

-export([start_link/4]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         handle_continue/2,
         terminate/2]).

-export_type([t/0,
              grpc_status/0,
              grpc_status_message/0,
              grpc_error/0,
              grpc_error_response/0,
              grpc_callback_error/0,
              grpc_error_data/0,
              grpc_extended_error_response/0]).

-record(state, {handler             :: pid(),
                peercert            :: public_key:der_encoded() | undefined,
                auth_fun,
                buffer              :: binary(),
                ctx                 :: ctx:t() | undefined,
                services_table      :: ets:tid(),
                req_headers=[]      :: list(),
                full_method         :: binary() | undefined,
                input_ref           :: reference() | undefined,
                callback_pid        :: pid() | undefined,
                connection          :: h2:connection(),
                request_encoding    :: gzip | identity | undefined,
                response_encoding   :: gzip | identity | undefined,
                content_type        :: proto | json | undefined,
                resp_headers=[]     :: list(),
                resp_trailers=[]    :: list(),
                headers_sent=false  :: boolean(),
                trailers_sent=false :: boolean(),
                client_done=false   :: boolean(),
                unary_interceptor   :: fun() | undefined,
                stream_interceptor  :: fun() | undefined,
                stream_id           :: h2:stream_id(),
                method              :: #method{} | undefined,
                stats_handler       :: module() | undefined,
                stats               :: term() | undefined}).

-type t() :: #state{}.

-type grpc_status_message() :: unicode:chardata() | undefined.
-type grpc_status() :: binary() | undefined.
-type http_status() :: integer().
-type grpc_error() :: {unicode:unicode_binary(), % containing a grpc_status() value as text
                       grpc_status_message()}.
-type grpc_error_response() :: {error, grpc_error(), #{headers => map(),
                                                       trailers => #{}}} |
                               {http_error, {http_status(), unicode:chardata()}, #{headers => map(),
                                                                                   trailers => #{}}} |
                               {error, term()}.
-type grpc_callback_error() :: {error, grpc_error(), #{headers => map(),
                                                       trailers => #{}}}.

-type grpc_error_data() :: #{
    status := grpc_status(),
    message := grpc_status_message(),
    trailers => map()
}.
-type grpc_extended_error_response() :: {grpc_extended_error, grpc_error_data()}.

start_link(Conn, StreamId, Headers, Opts) ->
    gen_server:start_link(?MODULE, [Conn, StreamId, Headers, Opts], []).

init([Conn, StreamId, Headers, #{services_table := ServicesTable,
                                 auth_fun := AuthFun,
                                 unary_interceptor := UnaryInterceptor,
                                 stream_interceptor := StreamInterceptor,
                                 stats_handler := StatsHandler,
                                 peercert := PeerCert}]) ->
    process_flag(trap_exit, true),
    State = #state{connection=Conn,
                   stream_id=StreamId,
                   services_table=ServicesTable,
                   buffer = <<>>,
                   auth_fun=AuthFun,
                   unary_interceptor=UnaryInterceptor,
                   stream_interceptor=StreamInterceptor,
                   peercert=PeerCert,
                   handler=self(),
                   stats_handler=StatsHandler},
    %% register for this stream's events. DATA that arrived before
    %% registration was buffered by the connection and is replayed in order,
    %% after the {continue, ...} callback has processed the request headers
    case h2:set_stream_handler(Conn, StreamId, self()) of
        ok ->
            {ok, State, {continue, {headers, Headers}}};
        {error, _} ->
            %% stream is already gone, e.g. reset by the client
            {stop, normal}
    end.

handle_headers(Headers, State=#state{ctx=_Ctx}) ->
    %% proplists:get_value(<<":method">>, Headers) =:= <<"POST">>,
    Metadata = grpcbox_utils:headers_to_metadata(Headers),
    Ctx = case parse_options(<<"grpc-timeout">>, Headers) of
              infinity ->
                  grpcbox_metadata:new_incoming_ctx(Metadata);
              D ->
                  Deadline = max(0, erlang:convert_time_unit(D, nanosecond, millisecond)),
                  erlang:start_timer(Deadline, self(), <<"grpc-timeout">>),
                  ctx:with_deadline_after(grpcbox_metadata:new_incoming_ctx(Metadata), D, nanosecond)
          end,

    FullPath = proplists:get_value(<<":path">>, Headers),
    %% wait to rpc_begin here since we need to know the method
    Ctx1 = ctx:with_value(Ctx, grpc_server_method, FullPath),
    State1=#state{ctx=Ctx2} = stats_handler(Ctx1, rpc_begin, {}, State#state{full_method=FullPath}),

    RequestEncoding = parse_options(<<"grpc-encoding">>, Headers),
    ResponseEncoding = parse_options(<<"grpc-accept-encoding">>, Headers),
    ContentType = parse_options(<<"content-type">>, Headers),

    RespHeaders = [{<<"user-agent">>, <<"grpc-erlang/0.1.0">>},
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
            end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"Method not found on server">>, State#state{ctx=Ctx})
    end;
handle_service_lookup(Ctx, _, State) ->
    State1 = State#state{ctx=Ctx,
                         resp_headers=[{<<"user-agent">>, <<"grpc-erlang/0.1.0">>}]},
    end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"failed parsing path">>, State1).

handle_auth(_Ctx, State=#state{auth_fun=AuthFun,
                               peercert=PeerCert,
                               method=#method{input={_, InputStreaming}}}) ->
    case authenticate(PeerCert, AuthFun) of
        {true, _Identity} ->
            case InputStreaming of
                true ->
                    Ref = make_ref(),
                    Pid = proc_lib:spawn_link(?MODULE, handle_streams,
                                              [Ref, State#state{handler=self()}]),
                    State#state{input_ref=Ref,
                                callback_pid=Pid};
                _ ->
                    State
            end;
        _ ->
            end_stream(?GRPC_STATUS_UNAUTHENTICATED, <<"">>, State)
    end.

authenticate(_, undefined) ->
    {true, undefined};
authenticate(Cert, Fun) when Cert =/= undefined ->
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

ctx_with_stream(Ctx, Stream) ->
    ctx:set(Ctx, ctx_stream_key, Stream).

from_ctx(Ctx) ->
    ctx:get(Ctx, ctx_stream_key).

handle_data(_, State=#state{method=undefined}) ->
    State;
handle_data(Bin, State=#state{request_encoding=Encoding,
                              buffer=Buffer}) ->
    try
        {NewBuffer, Messages} = grpcbox_frame:split(<<Buffer/binary, Bin/binary>>, Encoding),
        State1 = lists:foldl(fun(EncodedMessage, StateAcc=#state{}) ->
                                     StateAcc1 = handle_message(EncodedMessage, StateAcc),
                                     StateAcc1
                             end, State, Messages),
        State1#state{buffer=NewBuffer}
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
                    CallbackPid = proc_lib:spawn_link(?MODULE, handle_streams,
                                                      [Message, State1#state{handler=self()}]),
                    State1#state{callback_pid=CallbackPid};
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

end_of_stream(State0) ->
    end_of_stream_(State0#state{client_done=true}).

end_of_stream_(State=#state{input_ref=Ref,
                            callback_pid=Pid,
                            method=#method{input={_Input, true}}}) ->
    Pid ! {Ref, eos},
    State;
end_of_stream_(State=#state{callback_pid=undefined,
                            method=#method{input={_Input, false},
                                           output={_Output, true}}}) ->
    %% half-closed before a request message arrived, no handler was started
    %% so no one will ever end this stream
    end_stream(?GRPC_STATUS_INTERNAL, <<"half-closed without a request message">>, State);
end_of_stream_(State=#state{method=#method{input={_Input, false},
                                           output={_Output, true}}}) ->
    State;
end_of_stream_(State) ->
    end_stream(State).

%% gen_server callbacks

handle_call(ctx, _From, State=#state{ctx=Ctx}) ->
    {reply, Ctx, State};
handle_call({ctx, Ctx}, _From, State) ->
    {reply, ok, State#state{ctx=Ctx}}.

handle_cast(_, State) ->
    {noreply, State}.

handle_continue({headers, Headers}, State) ->
    try handle_headers(Headers, State) of
        State1 ->
            maybe_stop(State1)
    catch
        throw:{grpc_error, {Status, Message}} ->
            maybe_stop(end_stream(Status, Message, State#state{ctx=ctx:new()}))
    end.

handle_info({h2, Conn, Event}, State=#state{connection=Conn}) ->
    handle_event(Event, State);
handle_info({add_headers, Headers}, State) ->
    {noreply, update_headers(Headers, State)};
handle_info({add_trailers, Trailers}, State) ->
    {noreply, update_trailers(Trailers, State)};
handle_info({send_proto, Message}, State) ->
    {noreply, send(false, Message, State)};
handle_info({'EXIT', Pid, normal}, State=#state{callback_pid=Pid}) ->
    maybe_stop(end_stream(State));
handle_info({'EXIT', Pid, {grpc_error, {Status, Message}}}, State=#state{callback_pid=Pid}) ->
    maybe_stop(end_stream(Status, Message, State));
handle_info({'EXIT', Pid, {grpc_extended_error, #{status := Status, message := Message} = ErrorData}},
            State=#state{callback_pid=Pid}) ->
    State1 = add_trailers_from_error_data(ErrorData, State),
    maybe_stop(end_stream(Status, Message, State1));
handle_info({'EXIT', Pid, _Other}, State=#state{callback_pid=Pid}) ->
    maybe_stop(end_stream(?GRPC_STATUS_UNKNOWN, <<"process exited without reason">>, State));
handle_info({timeout, _Ref, <<"grpc-timeout">>}, State) ->
    maybe_stop(end_stream(?GRPC_STATUS_DEADLINE_EXCEEDED, <<"Deadline expired">>, State));
handle_info(_, State) ->
    {noreply, State}.

terminate(_Reason, State=#state{callback_pid=Pid}) when is_pid(Pid) ->
    exit(Pid, {shutdown, stream_terminated}),
    maybe_reset(State),
    ok;
terminate(_Reason, State) ->
    maybe_reset(State),
    ok.

%% the response is complete but the client's send side is still open: reset
%% the stream so it doesn't keep streaming into the void and the stream
%% doesn't stay half open on the connection
maybe_reset(#state{trailers_sent=true,
                   client_done=false,
                   connection=Conn,
                   stream_id=StreamId}) ->
    try h2:cancel(Conn, StreamId, no_error) catch _:_ -> ok end;
maybe_reset(_) ->
    ok.

handle_event({data, _StreamId, Bin, IsFin}, State) ->
    State1 = handle_data(Bin, State),
    State2 = case IsFin of
                 true ->
                     end_of_stream(State1);
                 false ->
                     State1
             end,
    maybe_stop(State2);
handle_event({trailers, _StreamId, _Trailers}, State) ->
    %% trailers from the client carry END_STREAM
    maybe_stop(end_of_stream(State));
handle_event({stream_reset, _StreamId, _ErrorCode}, State) ->
    {stop, {shutdown, stream_reset}, State};
handle_event({closed, _Reason}, State) ->
    {stop, {shutdown, connection_closed}, State};
handle_event(_, State) ->
    {noreply, State}.

maybe_stop(State=#state{trailers_sent=true}) ->
    {stop, normal, State};
maybe_stop(State) ->
    {noreply, State}.

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
    end_stream(Status, Message, send_headers_internal([], State));
end_stream(_Status, _Message, State=#state{trailers_sent=true}) ->
    State;
end_stream(Status, Message, State=#state{connection=Conn,
                                         stream_id=StreamId,
                                         ctx=Ctx,
                                         resp_trailers=Trailers}) ->
    EncodedTrailers = grpcbox_utils:encode_headers(Trailers),
    _ = h2:send_trailers(Conn, StreamId, [{<<"grpc-status">>, Status},
                                          {<<"grpc-message">>, Message} | EncodedTrailers]),
    Ctx1 = ctx:with_value(Ctx, grpc_server_status, grpcbox_utils:status_to_string(Status)),
    State1 = stats_handler(Ctx1, rpc_end, {}, State),
    State1#state{trailers_sent=true}.

set_trailers(Ctx, Trailers) ->
    State = from_ctx(Ctx),
    ctx_with_stream(Ctx, State#state{resp_trailers=maps:to_list(Trailers)}).

send_headers(Ctx, Headers) when is_map(Headers) ->
    State = from_ctx(Ctx),
    send_headers_internal(maps:to_list(maybe_encode_headers(Headers)), State);
send_headers(Metadata, State=#state{}) ->
    send_headers_internal(Metadata, State).

send_headers_internal(_Metadata, State=#state{headers_sent=true}) ->
    State;
send_headers_internal(Metadata, State=#state{connection=Conn,
                                             stream_id=StreamId,
                                             resp_headers=Headers,
                                             headers_sent=false}) ->
    MdHeaders = grpcbox_utils:encode_headers(Metadata),
    _ = h2:send_response(Conn, StreamId, 200, Headers ++ MdHeaders),
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
    gen_server:call(Pid, ctx).

ctx(#state{handler=Pid}, Ctx) ->
    gen_server:call(Pid, {ctx, Ctx}).

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
    State1 = send_headers_internal([], State),
    send(End, Message, State1);
send(End, Message, State=#state{ctx=Ctx,
                                connection=Conn,
                                stream_id=StreamId,
                                response_encoding=Encoding,
                                method=#method{proto=Proto,
                                               input={_Input, _},
                                               output={Output, _}}}) ->
    BodyToSend = Proto:encode_msg(Message, Output),
    OutFrame = grpcbox_frame:encode(Encoding, BodyToSend),
    %% block on flow control, bounded by the request deadline so the
    %% grpc-timeout still fires against a stalled client
    case h2:send_data(Conn, StreamId, OutFrame, End, #{block => block_timeout(Ctx)}) of
        {error, timeout} ->
            exit({shutdown, send_timeout});
        _ ->
            ok
    end,
    stats_handler(Ctx, out_payload, #{uncompressed_size => erlang:external_size(Message),
                                      compressed_size => size(BodyToSend)}, State).

block_timeout(Ctx) ->
    case ctx:deadline(Ctx) of
        D when D =:= undefined ; D =:= infinity ->
            infinity;
        {T, _} ->
            max(0, erlang:convert_time_unit(T - erlang:monotonic_time(), native, millisecond))
    end.

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
    T.

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
