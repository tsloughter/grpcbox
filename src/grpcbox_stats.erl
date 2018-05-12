-module(grpcbox_stats).

-export([register_measures/0,
         default_views/0,
         extra_views/0]).

register_measures() ->
    oc_stat_measure:new('grpc.io/server/received_messages_per_rpc',
                        "Number of messages received in each RPC. Has value 1 for non-streaming RPCs.",
                        none),
    oc_stat_measure:new('grpc.io/server/received_bytes_per_rpc',
                        "Total bytes received across all messages per RPC.",
                        bytes),
    oc_stat_measure:new('grpc.io/server/sent_messages_per_rpc',
                        "Number of messages sent in each RPC. Has value 1 for non-streaming RPCs.",
                        none),
    oc_stat_measure:new('grpc.io/server/sent_bytes_per_rpc',
                        "Total bytes sent in across all response messages per RPC.",
                        bytes),
    oc_stat_measure:new('grpc.io/server/server_latency',
                        "Time between first byte of request received to last byte of response sent, or terminal error.",
                        milli_seconds).


default_views() ->
    [#{name => "grpc.io/server/server_latency",
       description => "Distribution of time taken by request.",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/server_latency',
       aggregation => default_latency_distribution()},
     #{name => "grpc.io/server/sent_bytes_per_rpc",
       description => "Distribution of total bytes sent per RPC",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/sent_bytes_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/server/received_bytes_per_rpc",
       description => "Distribution of total bytes received per RPC",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/received_bytes_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/server/completed_rpcs",
       description => "Total count of completed rpcs",
       tags => [grpc_server_method, grpc_server_status],
       measure => 'grpc.io/server/latency',
       aggregation => oc_stat_aggregation_count}].

extra_views() ->
    [#{name => "grpc.io/server/received_messages_per_rpc",
       description => "Distribution of messages received per RPC",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/received_messages_per_rpc',
       aggregation => default_latency_distribution()},
     #{name => "grpc.io/server/sent_messages_per_rpc",
       description => "Distribution of messages sent per RPC",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/sent_messages_per_rpc',
       aggregation => default_size_distribution()}].

default_size_distribution() ->
    {oc_stat_aggregation_distribution, [{buckets, [0, 1024, 2048, 4096, 16384, 65536,
                                                   262144, 1048576, 4194304, 16777216,
                                                   67108864, 268435456, 1073741824,
                                                   4294967296]}]}.

default_latency_distribution() ->
    {oc_stat_aggregation_distribution, [{buckets, [0, 1, 2, 3, 4, 5, 6, 8, 10, 13, 16, 20, 25, 30,
                                                   40, 50, 65, 80, 100, 130, 160, 200, 250, 300, 400,
                                                   500, 650, 800, 1000, 2000, 5000, 10000, 20000, 50000,
                                                   100000]}]}.
