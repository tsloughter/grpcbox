%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.health.v1.Health.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-03-09T00:28:46+00:00 and should not be modified manually

-module(grpcbox_health_bhvr).

%% @doc Unary RPC
-callback check(ctx:ctx(), grpcbox_health_pb:health_check_request()) ->
    {ok, grpcbox_health_pb:health_check_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback watch(grpcbox_health_pb:health_check_request(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

