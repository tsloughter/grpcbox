-module(grpcbox_client_stream).

-behaviour(gen_server).

-export([new_stream/5,
         send_request/6,
         send_msg/2,
         recv_msg/2]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2]).

-include_lib("grpcbox/include/grpcbox.hrl").

new_stream(Ctx, Channel, Path, Def=#grpcbox_def{service=Service,
                                                message_type=MessageType,
                                                marshal_fun=MarshalFun,
                                                unmarshal_fun=UnMarshalFun}, Options) ->
    case grpcbox_subchannel:conn(Channel, grpcbox_utils:get_timeout_from_ctx(Ctx, infinity)) of
        {ok, Conn, #{scheme := Scheme,
                     authority := Authority,
                     encoding := DefaultEncoding,
                     stats_handler := StatsHandler}} ->
            Encoding = maps:get(encoding, Options, DefaultEncoding),
            RequestHeaders = headers(Scheme, Authority, Path, encoding_to_binary(Encoding),
                                      MessageType, metadata_headers(Ctx)),
            case start_stream(Conn, RequestHeaders,
                              stream_state(Service, MarshalFun, UnMarshalFun,
                                           Path, Encoding, StatsHandler)) of
                {error, _Code} = Err ->
                    Err;
                {ok, StreamId, Pid} ->
                    Ref = erlang:monitor(process, Pid),
                    {ok, #{channel => Conn,
                           stream_id => StreamId,
                           stream_pid => Pid,
                           monitor_ref => Ref,
                           service_def => Def,
                           encoding => Encoding}}
            end;
        {error, _}=Error ->
            Error
    end.

send_request(Ctx, Channel, Path, Input, #grpcbox_def{service=Service,
                                                     message_type=MessageType,
                                                     marshal_fun=MarshalFun,
                                                     unmarshal_fun=UnMarshalFun}, Options) ->
    case grpcbox_subchannel:conn(Channel, grpcbox_utils:get_timeout_from_ctx(Ctx, infinity)) of
        {ok, Conn, #{scheme := Scheme,
                     authority := Authority,
                     encoding := DefaultEncoding,
                     stats_handler := StatsHandler}} ->
            Encoding = maps:get(encoding, Options, DefaultEncoding),
            Body = grpcbox_frame:encode(Encoding, MarshalFun(Input)),
            Headers = headers(Scheme, Authority, Path, encoding_to_binary(Encoding), MessageType, metadata_headers(Ctx)),

            case start_stream(Conn, Headers,
                              stream_state(Service, MarshalFun, UnMarshalFun,
                                           Path, Encoding, StatsHandler)) of
                {error, _Code} = Err ->
                    Err;
                {ok, StreamId, Pid} ->
                    %% block on flow control instead of failing on a full
                    %% send buffer so large request messages go through
                    case h2:send_data(Conn, StreamId, Body, true, #{block => infinity}) of
                        ok ->
                            {ok, Conn, StreamId, Pid};
                        {error, Reason} when Reason =:= stream_closed ;
                                             Reason =:= stream_reset ->
                            %% the server already finished the rpc, e.g. a
                            %% Trailers-Only error response, its status is
                            %% delivered through the stream events
                            {ok, Conn, StreamId, Pid};
                        {error, _}=Err ->
                            _ = h2:cancel(Conn, StreamId, cancel),
                            catch gen_server:stop(Pid),
                            Err
                    end
            end;
        {error, _}=Error ->
            Error
    end.

stream_state(Service, MarshalFun, UnMarshalFun, Path, Encoding, StatsHandler) ->
    #{service => Service,
      marshal_fun => MarshalFun,
      unmarshal_fun => UnMarshalFun,
      path => Path,
      buffer => <<>>,
      encoding => Encoding,
      stats_handler => StatsHandler,
      stats => #{},
      client_pid => self()}.

%% start the stream process and open the stream on the connection with the
%% process registered as its handler, so all events for the stream go
%% directly to it
start_stream(Conn, Headers, StreamState) ->
    case gen_server:start(?MODULE, [Conn, StreamState], []) of
        {ok, Pid} ->
            case h2:request(Conn, Headers, #{handler => Pid,
                                             end_stream => false}) of
                {ok, StreamId} ->
                    gen_server:cast(Pid, {stream_id, StreamId}),
                    {ok, StreamId, Pid};
                {error, _}=Err ->
                    gen_server:stop(Pid),
                    Err
            end;
        {error, _}=Err ->
            Err
    end.

send_msg(#{channel := Conn,
           stream_id := StreamId,
           encoding := Encoding,
           service_def := #grpcbox_def{marshal_fun=MarshalFun}}, Input) ->
    OutFrame = grpcbox_frame:encode(Encoding, MarshalFun(Input)),
    %% block on flow control instead of failing on a full send buffer. A
    %% send on a stream or connection that is already gone is a no-op, the
    %% error is delivered to the caller through the stream events
    try h2:send_data(Conn, StreamId, OutFrame, false, #{block => infinity}) of
        _ ->
            ok
    catch
        exit:_ ->
            ok
    end.

recv_msg(S=#{stream_id := Id,
             stream_pid := Pid,
             monitor_ref := Ref}, Timeout) ->
    receive
        {data, Id, V} ->
            {ok, V};
        {'DOWN', Ref, process, Pid, _Reason} ->
            case grpcbox_client:recv_trailers(S, 0) of
                {ok, {<<"0">> = _Status, _Message, _Metadata}} ->
                    stream_finished;
                {ok, {Status, Message, Metadata}} ->
                    {error, {Status, Message}, #{trailers => Metadata}};
                {error, _} ->
                    stream_finished
            end
    after Timeout ->
            case erlang:is_process_alive(Pid) of
                true ->
                    timeout;
                false ->
                    stream_finished
            end
    end.

metadata_headers(Ctx) ->
    case ctx:deadline(Ctx) of
        D when D =:= undefined ; D =:= infinity ->
            grpcbox_utils:encode_headers(maps:to_list(grpcbox_metadata:from_outgoing_ctx(Ctx)));
        {T, _} ->
            TimeMs = erlang:convert_time_unit(T - erlang:monotonic_time(), native, millisecond),
            Timeout = {<<"grpc-timeout">>, <<(integer_to_binary(TimeMs))/binary, "m">>},
            grpcbox_utils:encode_headers([Timeout | maps:to_list(grpcbox_metadata:from_outgoing_ctx(Ctx))])
    end.

%% callbacks

init([Conn, State=#{path := Path,
                    client_pid := ClientPid}]) ->
    _ = erlang:monitor(process, Conn),
    _ = erlang:monitor(process, ClientPid),
    Ctx1 = ctx:with_value(ctx:new(), grpc_client_method, Path),
    State1 = stats_handler(Ctx1, rpc_begin, {}, State),
    {ok, State1#{conn => Conn}}.

handle_call(_, _From, State) ->
    {reply, ok, State}.

handle_cast({stream_id, StreamId}, State) ->
    {noreply, State#{stream_id => StreamId}};
handle_cast(_, State) ->
    {noreply, State}.

handle_info({h2, _Conn, Event}, State) ->
    handle_event(Event, State);
handle_info({'DOWN', _Ref, process, Pid, _Reason}, State=#{conn := Conn,
                                                           client_pid := Pid}) ->
    %% the process that started the stream is gone, reset the stream so the
    %% server doesn't keep it open
    case State of
        #{stream_id := StreamId} ->
            _ = h2:cancel(Conn, StreamId, cancel);
        _ ->
            ok
    end,
    {stop, normal, State};
handle_info({'DOWN', _Ref, process, _Pid, Reason}, State) ->
    %% the connection died
    {stop, {shutdown, {connection_down, Reason}}, State};
handle_info(_, State) ->
    {noreply, State}.

%% response headers. a grpc-status header means a Trailers-Only response
handle_event({response, StreamId, Status, RespHeaders}, State=#{ctx := Ctx,
                                                                client_pid := Pid}) ->
    H = [{<<":status">>, integer_to_binary(Status)} | RespHeaders],
    Encoding = proplists:get_value(<<"grpc-encoding">>, H, identity),
    Metadata = grpcbox_utils:headers_to_metadata(H),
    Pid ! {headers, StreamId, Metadata},
    case proplists:get_value(<<"grpc-status">>, H, undefined) of
        undefined ->
            {noreply, State#{encoding => encoding_to_atom(Encoding)}};
        GrpcStatus ->
            Message = proplists:get_value(<<"grpc-message">>, H, undefined),
            Pid ! {trailers, StreamId, {GrpcStatus, Message, Metadata}},
            Ctx1 = ctx:with_value(Ctx, grpc_client_status, grpcbox_utils:status_to_string(GrpcStatus)),
            {noreply, State#{ctx => Ctx1,
                             encoding => encoding_to_atom(Encoding)}}
    end;
handle_event({data, StreamId, Data, IsFin}, State=#{client_pid := Pid,
                                                    buffer := Buffer,
                                                    encoding := Encoding,
                                                    unmarshal_fun := UnmarshalFun}) ->
    {Remaining, Messages} = grpcbox_frame:split(<<Buffer/binary, Data/binary>>, Encoding),
    [Pid ! {data, StreamId, UnmarshalFun(Message)} || Message <- Messages],
    State1 = State#{buffer => Remaining},
    case IsFin of
        true ->
            end_of_stream(StreamId, State1);
        false ->
            {noreply, State1}
    end;
%% trailers end the stream
handle_event({trailers, StreamId, Trailers}, State=#{ctx := Ctx,
                                                     client_pid := Pid}) ->
    Status = proplists:get_value(<<"grpc-status">>, Trailers, undefined),
    Message = proplists:get_value(<<"grpc-message">>, Trailers, undefined),
    Metadata = grpcbox_utils:headers_to_metadata(Trailers),
    Pid ! {trailers, StreamId, {Status, Message, Metadata}},
    Ctx1 = ctx:with_value(Ctx, grpc_client_status, grpcbox_utils:status_to_string(Status)),
    end_of_stream(StreamId, State#{ctx => Ctx1});
handle_event({stream_reset, _StreamId, ErrorCode}, State) ->
    {stop, {shutdown, {stream_reset, ErrorCode}}, State};
handle_event({goaway, LastStreamId, _ErrorCode}, State=#{client_pid := Pid}) ->
    case maps:get(stream_id, State, undefined) of
        StreamId when is_integer(StreamId), StreamId > LastStreamId ->
            %% the server will never process this stream, it is safe to retry
            Pid ! {trailers, StreamId, {<<"14">>, <<"connection draining">>, #{}}},
            end_of_stream(StreamId, State);
        _ ->
            {noreply, State}
    end;
handle_event({closed, Reason}, State) ->
    {stop, {shutdown, {connection_closed, Reason}}, State};
handle_event(_, State) ->
    {noreply, State}.

end_of_stream(StreamId, State=#{conn := Conn,
                                ctx := Ctx,
                                client_pid := Pid}) ->
    Pid ! {eos, StreamId},
    %% if our send side is still open, reset the stream so it doesn't stay
    %% half open on the connection, counting against concurrent streams. A
    %% no-op when the stream is already fully closed
    try h2:cancel(Conn, StreamId, cancel) catch _:_ -> ok end,
    State1 = stats_handler(Ctx, rpc_end, {}, State),
    {stop, normal, State1}.

%%

stats_handler(Ctx, _, _, State=#{stats_handler := undefined}) ->
    State#{ctx => Ctx};
stats_handler(Ctx, Event, Stats, State=#{stats_handler := StatsHandler,
                                         stats := StatsState}) ->
    {Ctx1, StatsState1} = StatsHandler:handle(Ctx, client, Event, Stats, StatsState),
    State#{ctx => Ctx1,
           stats => StatsState1}.

encoding_to_atom(identity) -> identity;
encoding_to_atom(<<"identity">>) -> identity;
encoding_to_atom(<<"gzip">>) -> gzip;
encoding_to_atom(<<"deflate">>) -> deflate;
encoding_to_atom(<<"snappy">>) -> snappy;
encoding_to_atom(Custom) -> binary_to_atom(Custom, latin1).

encoding_to_binary(identity) -> <<"identity">>;
encoding_to_binary(gzip) -> <<"gzip">>;
encoding_to_binary(deflate) -> <<"deflate">>;
encoding_to_binary(snappy) -> <<"snappy">>;
encoding_to_binary(Custom) -> atom_to_binary(Custom, latin1).

headers(Scheme, Host, Path, Encoding, MessageType, MD) ->
    {UserAgent, FilteredMD} = case lists:keytake(<<"user-agent">>, 1, MD) of
        {value, {<<"user-agent">>, MDUserAgent}, MD1} -> {MDUserAgent, MD1};
        false -> {<<"grpc-erlang/0.9.2">>, MD}
    end,

    [
        {<<":method">>, <<"POST">>},
        {<<":path">>, Path},
        {<<":scheme">>, Scheme},
        {<<":authority">>, Host},
        {<<"grpc-encoding">>, Encoding},
        {<<"grpc-message-type">>, MessageType},
        {<<"content-type">>, <<"application/grpc+proto">>},
        {<<"user-agent">>, UserAgent},
        {<<"te">>, <<"trailers">>}
    | FilteredMD].
