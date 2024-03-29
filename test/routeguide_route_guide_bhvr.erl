%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service routeguide.RouteGuide.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2020-10-19T05:10:58+00:00 and should not be modified manually

-module(routeguide_route_guide_bhvr).

%% @doc Unary RPC
-callback get_feature(ctx:t(), route_guide_pb:point()) ->
    {ok, route_guide_pb:feature(), ctx:t()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback list_features(route_guide_pb:rectangle(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

%% @doc 
-callback record_route(reference(), grpcbox_stream:t()) ->
    {ok, route_guide_pb:route_summary(), ctx:t()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback route_chat(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback generate_error(ctx:t(), route_guide_pb:empty()) ->
    {ok, route_guide_pb:empty(), ctx:t()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback streaming_generate_error(route_guide_pb:empty(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

