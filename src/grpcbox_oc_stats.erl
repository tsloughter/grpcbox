-module(grpcbox_oc_stats).

-export([register_measures/0,
         register_measures/1,
         subscribe_views/0,
         default_views/0,
         default_views/1,
         extra_views/0,
         extra_views/1]).

%% grpc_client_method 	Full gRPC method name, including package, service and method,
%%                      e.g. google.bigtable.v2.Bigtable/CheckAndMutateRow
%% grpc_client_status 	gRPC server status code received, e.g. OK, CANCELLED, DEADLINE_EXCEEDED

%% grpc_server_method 	Full gRPC method name, including package, service and method,
%%                       e.g. com.exampleapi.v4.BookshelfService/Checkout
%% grpc_server_status 	gRPC server status code returned, e.g. OK, CANCELLED, DEADLINE_EXCEEDED

register_measures() ->
    register_measures(client),
    register_measures(server).

-spec register_measures(client | server) -> ok.
register_measures(Type) ->
    [oc_stat_measure:new(Name, Desc, Unit) || {Name, Desc, Unit} <- register_measures_(Type)],
    ok.

register_measures_(client) ->
    [{'grpc.io/client/sent_messages_per_rpc',
      "Number of messages sent in each RPC (always 1 for non-streaming RPCs).",
      none},
     {'grpc.io/client/sent_bytes_per_rpc',
      "Total bytes sent in across all request messages per RPC.",
      bytes},
     {'grpc.io/client/received_messages_per_rpc',
      "Number of response messages received per RPC (always 1 for non-streaming RPCs).",
      none},
     {'grpc.io/client/received_bytes_per_rpc',
      "Total bytes received across all response messages per RPC.",
      bytes},
     {'grpc.io/client/roundtrip_latency',
      "Time between first byte of request sent to last byte of response received, or terminal error.",
      microsecond},
     {'grpc.io/client/server_latency',
      "Propagated from the server and should have the same value as grpc.io/server/latency.",
      microsecond},
     {'grpc.io/client/started_rpcs',
      "The total number of client RPCs ever opened, including those that have not completed.",
      none}];
register_measures_(server) ->
    [{'grpc.io/server/received_messages_per_rpc',
      "Number of messages received in each RPC. Has value 1 for non-streaming RPCs.",
      none},
     {'grpc.io/server/received_bytes_per_rpc',
      "Total bytes received across all messages per RPC.",
      bytes},
     {'grpc.io/server/sent_messages_per_rpc',
      "Number of messages sent in each RPC. Has value 1 for non-streaming RPCs.",
      none},
     {'grpc.io/server/sent_bytes_per_rpc',
      "Total bytes sent in across all response messages per RPC.",
      bytes},
     {'grpc.io/server/server_latency',
      "Time between first byte of request received to last byte of response sent, or terminal error.",
      microsecond},
     {'grpc.io/server/started_rpcs',
      "The total number of server RPCs ever opened, including those that have not completed.",
      none}].

subscribe_views() ->
    [oc_stat_view:subscribe(V) || V <- default_views()].

default_views() ->
    default_views(client) ++ default_views(server).

default_views(client) ->
    [#{name => "grpc.io/client/sent_bytes_per_rpc",
       description => "Distribution of total bytes sent per RPC",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/sent_bytes_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/client/received_bytes_per_rpc",
       description => "Distribution of total bytes received per RPC",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/received_bytes_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/client/roundtrip_latency",
       description => "Distribution of time taken by request.",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/roundtrip_latency',
       unit => microsecond,
       aggregation => default_latency_distribution()},
     #{name => "grpc.io/client/completed_rpcs",
       description => "Total count of completed rpcs",
       tags => [grpc_client_method, grpc_client_status],
       measure => 'grpc.io/client/roundtrip_latency',
       aggregation => oc_stat_aggregation_count},
     #{name => "grpc.io/client/started_rpcs",
       description => "The total number of client RPCs ever opened, including those that have not completed.",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/started_rpcs',
       aggregation => oc_stat_aggregation_count}];
default_views(server) ->
    [#{name => "grpc.io/server/received_bytes_per_rpc",
       description => "Distribution of total bytes received per RPC",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/received_bytes_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/server/sent_bytes_per_rpc",
       description => "Distribution of total bytes sent per RPC",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/sent_bytes_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/server/server_latency",
       description => "Distribution of time taken by request.",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/server_latency',
       unit => microsecond,
       aggregation => default_latency_distribution()},
     #{name => "grpc.io/server/completed_rpcs",
       description => "Total count of completed rpcs",
       tags => [grpc_server_method, grpc_server_status],
       measure => 'grpc.io/server/server_latency',
       aggregation => oc_stat_aggregation_count},
     #{name => "grpc.io/server/started_rpcs",
       description => "The total number of server RPCs ever opened, including those that have not completed.",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/started_rpcs',
       aggregation => oc_stat_aggregation_count}].

extra_views() ->
    extra_views(client),
    extra_views(server).

extra_views(client) ->
    [#{name => "grpc.io/client/received_messages_per_rpc",
       description => "Distribution of messages received per RPC",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/received_messages_per_rpc',
       unit => microsecond,
       aggregation => default_latency_distribution()},
     #{name => "grpc.io/client/sent_messages_per_rpc",
       description => "Distribution of messages sent per RPC",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/sent_messages_per_rpc',
       aggregation => default_size_distribution()},
     #{name => "grpc.io/client/server_latency",
       description => "Distribution of latency value propagated from the server.",
       tags => [grpc_client_method],
       measure => 'grpc.io/client/server_latency',
       unit => microsecond,
       aggregation => default_latency_distribution()}];
extra_views(server) ->
    [#{name => "grpc.io/server/received_messages_per_rpc",
       description => "Distribution of messages received per RPC",
       tags => [grpc_server_method],
       measure => 'grpc.io/server/received_messages_per_rpc',
       unit => microsecond,
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
    {oc_stat_aggregation_distribution,
     [{buckets, [0, 1000, 2000, 3000, 4000, 5000, 6000, 8000,
                 10000, 13000, 16000, 20000, 25000, 30000, 40000, 50000, 65000, 80000,
                 100000, 130000, 160000, 200000, 250000, 300000, 400000, 500000, 650000, 800000,
                 1000000, 2000000, 5000000, 10000000, 20000000, 50000000,
                 100000000]}]}.
