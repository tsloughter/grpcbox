%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service routeguide.RouteGuide.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-02-07T00:12:38+00:00 and should not be modified manually

-module(routeguide_route_guide_bhvr).

%% @doc Unary RPC
-callback get_feature(ctx:ctx(), route_guide_pb:point()) ->
    {ok, route_guide_pb:feature(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback list_features(route_guide_pb:rectangle(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

%% @doc 
-callback record_route(reference(), grpcbox_stream:t()) ->
    {ok, route_guide_pb:route_summary(), ctx:ctx()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback route_chat(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

