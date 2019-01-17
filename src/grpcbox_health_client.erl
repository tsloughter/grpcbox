%%%-------------------------------------------------------------------
%% @doc Client module for grpc service grpc.health.v1.Health.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-01-17T19:47:53+00:00 and should not be modified manually

-module(grpcbox_health_client).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("grpcbox/include/grpcbox.hrl").

-define(SERVICE, 'grpc.health.v1.Health').
-define(PROTO_MODULE, 'grpcbox_health_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output), #grpcbox_def{service=?SERVICE,
                                         marshal_fun=?MARSHAL_FUN(Input),
                                         unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc Unary RPC
-spec check(ctx:t(), grpcbox_health_pb:health_check_request()) ->
    {ok, grpcbox_health_pb:health_check_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
check(Ctx, Input) ->
    check(Ctx, Input, #{}).

-spec check(ctx:t(), grpcbox_health_pb:health_check_request(), grpcbox_client:options()) ->
    {ok, grpcbox_health_pb:health_check_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
check(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.health.v1.Health/Check">>, Input, ?DEF(health_check_request, health_check_response), Options).

%% @doc 
-spec watch(ctx:t(), grpcbox_health_pb:health_check_request()) ->
    {ok, grpcbox_stream:t()} | grpcbox_stream:grpc_error_response().
watch(Ctx, Input) ->
    watch(Ctx, Input, #{}).

-spec watch(ctx:t(), grpcbox_health_pb:health_check_request(), grpcbox_client:options()) ->
    {ok, grpcbox_stream:t()} | grpcbox_stream:grpc_error_response().
watch(Ctx, Input, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.health.v1.Health/Watch">>, Input, ?DEF(health_check_request, health_check_response), Options).

