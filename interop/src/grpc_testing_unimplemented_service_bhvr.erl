%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.testing.UnimplementedService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2017-12-08T01:24:35+00:00 and should not be modified manually

-module(grpc_testing_unimplemented_service_bhvr).

%% @doc Unary RPC
-callback unimplemented_call(ctx:ctx(), test_pb:'grpc.testing.Empty'()) ->
    {ok, test_pb:'grpc.testing.Empty'()} | grpcbox_stream:grpc_error_response().

