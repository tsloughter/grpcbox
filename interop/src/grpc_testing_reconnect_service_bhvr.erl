%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.testing.ReconnectService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-02-02T14:54:28+00:00 and should not be modified manually

-module(grpc_testing_reconnect_service_bhvr).

%% @doc Unary RPC
-callback start(ctx:ctx(), test_pb:reconnect_params()) ->
    {ok, test_pb:empty(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback stop(ctx:ctx(), test_pb:empty()) ->
    {ok, test_pb:reconnect_info(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

