-module(grpcbox_oc_stats_handler).

-export([init/0,
         init/1,
         handle/4]).

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

handle(Ctx, rpc_begin, _, _) ->
    {Ctx, #stats{start_time=erlang:monotonic_time()}};
handle(Ctx, out_payload, #{uncompressed_size := USize,
                           compressed_size := _CSize}, Stats=#stats{sent_count=SentCount,
                                                                    sent_bytes=SentBytes}) ->

    {Ctx, Stats#stats{sent_count=SentCount+1,
                      sent_bytes=SentBytes+USize}};
handle(Ctx, in_payload, #{uncompressed_size := USize,
                          compressed_size := _CSize}, Stats=#stats{recv_count=SentCount,
                                                                   recv_bytes=SentBytes}) ->

    {Ctx, Stats#stats{recv_count=SentCount+1,
                      recv_bytes=SentBytes+USize}};
handle(Ctx, rpc_end, _, Stats=#stats{start_time=StartTime,
                                     sent_count=SentCount,
                                     sent_bytes=SentBytes,
                                     recv_count=RecvCount,
                                     recv_bytes=RecvBytes}) ->
    EndTime = erlang:monotonic_time(),
    oc_stat:record(Ctx, [{'grpc.io/server/server_latency', EndTime - StartTime},
                         {'grpc.io/server/sent_bytes_per_rpc', SentBytes},
                         {'grpc.io/server/received_bytes_per_rpc', RecvBytes},
                         {'grpc.io/server/received_messages_per_rpc', RecvCount},
                         {'grpc.io/server/sent_messages_per_rpc', SentCount}]),

    {Ctx, Stats#stats{end_time=EndTime}};
handle(Ctx, _, _, Stats=#stats{}) ->
    {Ctx, Stats}.
