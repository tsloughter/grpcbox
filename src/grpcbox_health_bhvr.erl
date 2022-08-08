%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.health.v1.Health.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated and should not be modified manually

-module(grpcbox_health_bhvr).

%% Unary RPC
-callback check(ctx:t(), grpcbox_health_pb:health_check_request()) ->
    {ok, grpcbox_health_pb:health_check_response(), ctx:t()} | grpcbox_stream:grpc_error_response().

%% 
-callback watch(grpcbox_health_pb:health_check_request(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

