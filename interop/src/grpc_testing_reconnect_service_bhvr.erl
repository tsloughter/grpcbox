%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.testing.ReconnectService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2018-01-07T20:10:35+00:00 and should not be modified manually

-module(grpc_testing_reconnect_service_bhvr).

%% @doc Unary RPC
-callback start(ctx:ctx(), test_pb:'grpc.testing.ReconnectParams'()) ->
    {ok, test_pb:'grpc.testing.Empty'()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback stop(ctx:ctx(), test_pb:'grpc.testing.Empty'()) ->
    {ok, test_pb:'grpc.testing.ReconnectInfo'()} | grpcbox_stream:grpc_error_response().

