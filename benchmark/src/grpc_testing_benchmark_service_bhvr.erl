%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.testing.BenchmarkService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2021-12-29T09:28:22+00:00 and should not be modified manually

-module(grpc_testing_benchmark_service_bhvr).

%% @doc Unary RPC
-callback unary_call(ctx:ctx(), benchmark_service_pb:simple_request()) ->
    {ok, benchmark_service_pb:simple_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback streaming_call(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

%% @doc 
-callback streaming_from_client(reference(), grpcbox_stream:t()) ->
    {ok, benchmark_service_pb:simple_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback streaming_from_server(benchmark_service_pb:simple_request(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

%% @doc 
-callback streaming_both_ways(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

