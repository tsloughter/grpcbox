-module(grpcbox_client_stream).

-export([new_stream/5,
         send_request/6,
         send_msg/2,
         recv_msg/2,

         init/3,
         on_receive_headers/2,
         on_receive_data/2,
         on_end_stream/1,
         handle_info/2]).

-include("grpcbox.hrl").

-define(protected_headers, [<<"content-type">>, <<"te">>]).
-define(pseudoheaders(Path, Scheme, Authority), [{<<":method">>, <<"POST">>},
                                                 {<<":path">>, Path},
                                                 {<<":scheme">>, Scheme},
                                                 {<<":authority">>, Authority}]).
-define(headers(Encoding, MessageType, MD), (MD ++ [{<<"grpc-encoding">>, Encoding},
                                                   {<<"grpc-message-type">>, MessageType},
                                                   {<<"content-type">>, <<"application/grpc+proto">>},
                                                   {<<"user-agent">>, <<"grpc-erlang/0.9.2">>},
                                                   {<<"te">>, <<"trailers">>}])).

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
            UserHeaders = merge_headers(?headers(encoding_to_binary(Encoding), MessageType, metadata_headers(Ctx))),
            RequestHeaders = ?pseudoheaders(Path, Scheme, Authority) ++ UserHeaders,

            case h2_connection:new_stream(Conn, ?MODULE, [#{service => Service,
                                                            marshal_fun => MarshalFun,
                                                            unmarshal_fun => UnMarshalFun,
                                                            path => Path,
                                                            buffer => <<>>,
                                                            stats_handler => StatsHandler,
                                                            stats => #{},
                                                            client_pid => self()}], RequestHeaders, [], self()) of
                {error, _Code} = Err ->
                    Err;
                {StreamId, Pid} ->
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
            UserHeaders = merge_headers(?headers(encoding_to_binary(Encoding), MessageType, metadata_headers(Ctx))),
            RequestHeaders = ?pseudoheaders(Path, Scheme, Authority) ++ UserHeaders,

            %% headers are sent in the same request as creating a new stream to ensure
            %% concurrent calls can't end up interleaving the sending of headers in such
            %% a way that a lower stream id's headers are sent after another's, which results
            %% in the server closing the connection when it gets them out of order
            case h2_connection:new_stream(Conn, grpcbox_client_stream, [#{service => Service,
                                                                          marshal_fun => MarshalFun,
                                                                          unmarshal_fun => UnMarshalFun,
                                                                          path => Path,
                                                                          buffer => <<>>,
                                                                          stats_handler => StatsHandler,
                                                                          stats => #{},
                                                                          client_pid => self()}], RequestHeaders, [], self()) of
                {error, _Code} = Err ->
                    Err;
                {StreamId, Pid} ->
                    h2_connection:send_body(Conn, StreamId, Body),
                    {ok, Conn, StreamId, Pid}
            end;
        {error, _}=Error ->
            Error
    end.

send_msg(#{channel := Conn,
           stream_id := StreamId,
           encoding := Encoding,
           service_def := #grpcbox_def{marshal_fun=MarshalFun}}, Input) ->
    OutFrame = grpcbox_frame:encode(Encoding, MarshalFun(Input)),
    h2_connection:send_body(Conn, StreamId, OutFrame, [{send_end_stream, false}]).

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

init(_ConnectionPid, StreamId, [_, State=#{path := Path}]) ->
    _ = process_flag(trap_exit, true),
    Ctx1 = ctx:with_value(ctx:new(), grpc_client_method, Path),
    State1 = stats_handler(Ctx1, rpc_begin, {}, State),
    {ok, State1#{stream_id => StreamId}};
init(_, _, State) ->
    {ok, State}.

%% trailers
on_receive_headers(H, State=#{resp_headers := _,
                              ctx := Ctx,
                              stream_id := StreamId,
                              client_pid := Pid}) ->
    Status = proplists:get_value(<<"grpc-status">>, H, undefined),
    Message = proplists:get_value(<<"grpc-message">>, H, undefined),
    Metadata = grpcbox_utils:headers_to_metadata(H),
    Pid ! {trailers, StreamId, {Status, Message, Metadata}},
    Ctx1 = ctx:with_value(Ctx, grpc_client_status, grpcbox_utils:status_to_string(Status)),
    {ok, State#{ctx => Ctx1,
                resp_trailers => H}};
%% headers
on_receive_headers(H, State=#{stream_id := StreamId,
                              ctx := Ctx,
                              client_pid := Pid}) ->
    Encoding = proplists:get_value(<<"grpc-encoding">>, H, identity),
    Metadata = grpcbox_utils:headers_to_metadata(H),
    Pid ! {headers, StreamId, Metadata},
    %% TODO: better way to know if it is a Trailers-Only response?
    %% maybe chatterbox should include information about the end of the stream
    case proplists:get_value(<<"grpc-status">>, H, undefined) of
        undefined ->
            {ok, State#{resp_headers => H,
                        encoding => encoding_to_atom(Encoding)}};
        Status ->
            Message = proplists:get_value(<<"grpc-message">>, H, undefined),
            Pid ! {trailers, StreamId, {Status, Message, Metadata}},
            Ctx1 = ctx:with_value(Ctx, grpc_client_status, grpcbox_utils:status_to_string(Status)),
            {ok, State#{resp_headers => H,
                        ctx => Ctx1,
                        status => Status,
                        encoding => encoding_to_atom(Encoding)}}
    end.

on_receive_data(Data, State=#{stream_id := StreamId,
                              client_pid := Pid,
                              buffer := Buffer,
                              encoding := Encoding,
                              unmarshal_fun := UnmarshalFun}) ->
    {Remaining, Messages} = grpcbox_frame:split(<<Buffer/binary, Data/binary>>, Encoding),
    [Pid ! {data, StreamId, UnmarshalFun(Message)} || Message <- Messages],
    {ok, State#{buffer => Remaining}};
on_receive_data(_Data, State) ->
    {ok, State}.

on_end_stream(State=#{stream_id := StreamId,
                      ctx := Ctx,
                      client_pid := Pid}) ->
    Pid ! {eos, StreamId},
    State1 = stats_handler(Ctx, rpc_end, {}, State),
    {ok, State1}.

handle_info(_, State) ->
    State.

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

merge_headers(Headers) ->
    lists:foldl(fun merge_header_field/2, [], Headers).

merge_header_field({K, V}, HeadersAcc) ->
    case {is_protected_header(K), proplists:is_defined(K, HeadersAcc)} of
        {true, true} ->
            % is protected and already exists, skip
            HeadersAcc;
        {false, true} ->
            % isn't protected and already exists, join
            join_header_values({K, V}, HeadersAcc);
        {_, false} ->
            % doesn't exist, add
            [{K, V} | HeadersAcc]
    end.

join_header_values({Name, Val}, HeadersAcc) ->
    OrigVal = proplists:get_value(Name, HeadersAcc),
    NewValue = <<OrigVal/binary, <<", ">>/binary, Val/binary>>,
    NewList = lists:keyreplace(Name, 1, HeadersAcc, {Name, NewValue}),
    NewList.

is_protected_header(Name) ->
    lists:member(Name, ?protected_headers).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

merge_headers_test() ->
    {Encoding, MsgType} = {<<"identity">>, <<"grpc.TestRequest">>},
    Ctx = ctx:new(),
    Ctx1 = grpcbox_metadata:append_to_outgoing_ctx(Ctx, #{<<"content-type">> => <<"application/grpc">>,
                                                          <<"user-agent">> => <<"custom-grpc-client">>}),
    Headers0 = ?headers(Encoding, MsgType, metadata_headers(Ctx1)),
    Headers1 = merge_headers(Headers0),

    ?assertEqual([{<<"te">>, <<"trailers">>},
                  {<<"grpc-message-type">>, <<"grpc.TestRequest">>},
                  {<<"grpc-encoding">>, <<"identity">>},
                  {<<"user-agent">>, <<"custom-grpc-client, grpc-erlang/0.9.2">>},
                  {<<"content-type">>, <<"application/grpc">>}
                 ], Headers1),
    ok.

merge_headers_empty_ctx_test() ->
    {Encoding, MsgType} = {<<"identity">>, <<"grpc.TestRequest">>},
    Ctx = ctx:new(),
    Headers0 = ?headers(Encoding, MsgType, metadata_headers(Ctx)),
    Headers1 = merge_headers(Headers0),

    ?assertEqual([{<<"te">>, <<"trailers">>},
                  {<<"user-agent">>, <<"grpc-erlang/0.9.2">>},
                  {<<"content-type">>, <<"application/grpc+proto">>},
                  {<<"grpc-message-type">>, <<"grpc.TestRequest">>},
                  {<<"grpc-encoding">>, <<"identity">>}
                 ], Headers1),
    ok.

-endif.
