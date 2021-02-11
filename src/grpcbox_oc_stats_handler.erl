-module(grpcbox_oc_stats_handler).

-export([init/0,
         init/1,
         handle/5]).

-record(stats, {recv_bytes    = 0 :: integer(),
                sent_bytes    = 0 :: integer(),
                recv_count    = 0 :: integer(),
                sent_count    = 0 :: integer(),
                start_time        :: integer() | undefined,
                end_time          :: integer() | undefined}).

init() ->
    init(client),
    init(server).

-spec init(server | client) -> ok.
init(Type) ->
    grpcbox_oc_stats:register_measures(Type).

handle(Ctx, server, rpc_begin, _, _) ->
    Method = ctx:get(Ctx, grpc_server_method),
    Tags = #{grpc_server_method => Method},
    oc_stat:record(Tags, [{'grpc.io/server/started_rpcs', 1}]),
    {oc_tags:new(Ctx, Tags), #stats{start_time=erlang:monotonic_time(microsecond)}};
handle(Ctx, client, rpc_begin, _, _) ->
    Method = ctx:get(Ctx, grpc_client_method),
    Tags = #{grpc_client_method => Method},
    oc_stat:record(Tags, 'grpc.io/client/started_rpcs', 1),
    {oc_tags:new(Ctx, Tags), #stats{start_time=erlang:monotonic_time(microsecond)}};
handle(Ctx, _, out_payload, #{uncompressed_size := USize,
                              compressed_size := _CSize}, Stats=#stats{sent_count=SentCount,
                                                                       sent_bytes=SentBytes}) ->
    %% set span message event
    {Ctx, Stats#stats{sent_count=SentCount+1,
                      sent_bytes=SentBytes+USize}};
handle(Ctx, _, in_payload, #{uncompressed_size := USize,
                             compressed_size := _CSize}, Stats=#stats{recv_count=SentCount,
                                                                      recv_bytes=SentBytes}) ->
    %% set span message event
    {Ctx, Stats#stats{recv_count=SentCount+1,
                      recv_bytes=SentBytes+USize}};
handle(Ctx, server, rpc_end, _, Stats=#stats{start_time=StartTime,
                                             sent_count=SentCount,
                                             sent_bytes=SentBytes,
                                             recv_count=RecvCount,
                                             recv_bytes=RecvBytes}) ->
    EndTime = erlang:monotonic_time(microsecond),
    Status = ctx:get(Ctx, grpc_server_status),
    Ctx1 = oc_tags:new(Ctx, #{grpc_server_status => Status}),
    oc_stat:record(Ctx1, [{'grpc.io/server/server_latency', EndTime - StartTime},
                          {'grpc.io/server/sent_bytes_per_rpc', SentBytes},
                          {'grpc.io/server/received_bytes_per_rpc', RecvBytes},
                          {'grpc.io/server/received_messages_per_rpc', RecvCount},
                          {'grpc.io/server/sent_messages_per_rpc', SentCount}]),

    {Ctx1, Stats#stats{end_time=EndTime}};
handle(Ctx, client, rpc_end, _, Stats=#stats{start_time=StartTime,
                                             sent_count=SentCount,
                                             sent_bytes=SentBytes,
                                             recv_count=RecvCount,
                                             recv_bytes=RecvBytes}) ->
    EndTime = erlang:monotonic_time(microsecond),
    Status = ctx:get(Ctx, grpc_client_status),
    Ctx1 = oc_tags:new(Ctx, #{grpc_client_status => Status}),
    oc_stat:record(Ctx1, [{'grpc.io/client/roundtrip_latency', EndTime - StartTime},
                          {'grpc.io/client/sent_bytes_per_rpc', SentBytes},
                          {'grpc.io/client/received_bytes_per_rpc', RecvBytes},
                          {'grpc.io/client/received_messages_per_rpc', RecvCount},
                          {'grpc.io/client/sent_messages_per_rpc', SentCount}]),

    {Ctx1, Stats#stats{end_time=EndTime}};
handle(Ctx, _, _, _, Stats=#stats{}) ->
    {Ctx, Stats}.
