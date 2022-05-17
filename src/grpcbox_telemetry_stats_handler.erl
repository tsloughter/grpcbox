-module(grpcbox_telemetry_stats_handler).

-export([handle/5]).

-define(META_CTX, tel_meta_ctx_key).

-record(stats, {recv_bytes = 0 :: integer(),
                sent_bytes = 0 :: integer(),
                recv_count = 0 :: integer(),
                sent_count = 0 :: integer(),
                start_time     :: integer() | undefined,
                end_time       :: integer() | undefined}).

handle(Ctx, server, rpc_begin, _, _) ->
    Method = ctx:get(Ctx, grpc_server_method),
    Metadata = #{grpc_server_method => Method},
    StartTime = erlang:monotonic_time(),
    telemetry:execute([grpcbox, server, rpc_begin], #{start_time => StartTime}, Metadata),
    {put_meta(Ctx, Metadata), #stats{start_time=StartTime}};
handle(Ctx, client, rpc_begin, _, _) ->
    Method = ctx:get(Ctx, grpc_client_method),
    Metadata = #{grpc_client_method => Method},
    StartTime = erlang:monotonic_time(),
    telemetry:execute([grpcbox, client, rpc_begin], #{start_time => StartTime}, Metadata),
    {put_meta(Ctx, Metadata), #stats{start_time=StartTime}};
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
    EndTime = erlang:monotonic_time(),
    Status = ctx:get(Ctx, grpc_server_status),
    Metadata = maps:merge(get_meta(Ctx), #{grpc_server_status => Status}),
    Measurements = #{end_time => EndTime,
                     server_latency => EndTime - StartTime,
                     send_bytes_per_rpc => SentBytes,
                     received_bytes_per_rpc => RecvBytes,
                     received_messages_per_rpc => RecvCount,
                     sent_messages_per_rpc => SentCount},
    telemetry:execute([grpcbox, server, rpc_end], Measurements, Metadata),
    {put_meta(Ctx, Metadata), Stats#stats{end_time=EndTime}};
handle(Ctx, client, rpc_end, _, Stats=#stats{start_time=StartTime,
                                             sent_count=SentCount,
                                             sent_bytes=SentBytes,
                                             recv_count=RecvCount,
                                             recv_bytes=RecvBytes}) ->
    EndTime = erlang:monotonic_time(),
    Status = ctx:get(Ctx, grpc_client_status),
    Metadata = maps:merge(get_meta(Ctx), #{grpc_client_status => Status}),
    Measurements = #{end_time => EndTime,
                     roundtrip_latency => EndTime - StartTime,
                     sent_bytes_per_rpc => SentBytes,
                     received_bytes_per_rpc => RecvBytes,
                     received_messages_per_rpc => RecvCount,
                     sent_messages_per_rpc => SentCount},
    telemetry:execute([grpcbox, client, rpc_end], Measurements, Metadata),
    {put_meta(Ctx, Metadata), Stats#stats{end_time=EndTime}};
handle(Ctx, _, _, _, Stats=#stats{}) ->
    {Ctx, Stats}.

put_meta(Ctx, Map) ->
    ctx:with_value(Ctx, ?META_CTX, Map).

get_meta(Ctx) ->
    ctx:get(Ctx, ?META_CTX, #{}).
