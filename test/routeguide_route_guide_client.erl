%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service routeguide.RouteGuide.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2018-06-24T20:43:59+00:00 and should not be modified manually

-module(routeguide_route_guide_client).

-compile([nowarn_export_all]).
-compile([export_all]).

-include("grpcbox.hrl").

-define(SERVICE, 'routeguide.RouteGuide').
-define(PROTO_MODULE, 'route_guide_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output), #grpcbox_def{service=?SERVICE,
                                         marshal_fun=?MARSHAL_FUN(Input),
                                         unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc Unary RPC
-spec get_feature(ctx:t(), route_guide_pb:point()) ->
    {ok, route_guide_pb:feature(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_feature(Ctx, Input) ->
    get_feature(Ctx, Input, #{}).

-spec get_feature(ctx:t(), route_guide_pb:point(), grpcbox_client:options()) ->
    {ok, route_guide_pb:feature(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
get_feature(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/routeguide.RouteGuide/GetFeature">>, Input, ?DEF(point, feature), Options).

%% @doc 
-spec list_features(ctx:t(), route_guide_pb:rectangle()) ->
    {ok, grpcbox_stream:t()} | grpcbox_stream:grpc_error_response().
list_features(Ctx, Input) ->
    list_features(Ctx, Input, #{}).

-spec list_features(ctx:t(), route_guide_pb:rectangle(), grpcbox_client:options()) ->
    {ok, grpcbox_stream:t()} | grpcbox_stream:grpc_error_response().
list_features(Ctx, Input, Options) ->
    grpcbox_client:stream(Ctx, <<"/routeguide.RouteGuide/ListFeatures">>, Input, ?DEF(rectangle, feature), Options).

%% @doc 
-spec record_route(ctx:t()) ->
    {ok, grpcbox_stream:t()} | grpcbox_stream:grpc_error_response().
record_route(Ctx) ->
    record_route(Ctx, #{}).

-spec record_route(ctx:t(), grpcbox_client:options()) ->
    {ok, grpcbox_stream:t()} | grpcbox_stream:grpc_error_response().
record_route(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/routeguide.RouteGuide/RecordRoute">>, ?DEF(point, route_summary), Options).

%% @doc 
-spec route_chat(ctx:t()) ->
    {ok, grpclient:stream()} | grpcbox_stream:grpc_error_response().
route_chat(Ctx) ->
    route_chat(Ctx, #{}).

-spec route_chat(ctx:t(), grpcbox_client:options()) ->
    {ok, grpclient:stream()} | grpcbox_stream:grpc_error_response().
route_chat(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/routeguide.RouteGuide/RouteChat">>, ?DEF(route_note, route_note), Options).

