%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.testing.ReconnectService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2018-06-28T22:22:37+00:00 and should not be modified manually

-module(grpc_testing_reconnect_service_client).

-compile([nowarn_export_all]).
-compile([export_all]).

-include("grpcbox.hrl").

-define(SERVICE, 'grpc.testing.ReconnectService').
-define(PROTO_MODULE, 'test_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output), #grpcbox_def{service=?SERVICE,
                                         marshal_fun=?MARSHAL_FUN(Input),
                                         unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc Unary RPC
-spec start(ctx:t(), test_pb:reconnect_params()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
start(Ctx, Input) ->
    start(Ctx, Input, #{}).

-spec start(ctx:t(), test_pb:reconnect_params(), grpcbox_client:options()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
start(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.ReconnectService/Start">>, Input, ?DEF(reconnect_params, empty), Options).

%% @doc Unary RPC
-spec stop(ctx:t(), test_pb:empty()) ->
    {ok, test_pb:reconnect_info(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
stop(Ctx, Input) ->
    stop(Ctx, Input, #{}).

-spec stop(ctx:t(), test_pb:empty(), grpcbox_client:options()) ->
    {ok, test_pb:reconnect_info(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
stop(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.ReconnectService/Stop">>, Input, ?DEF(empty, reconnect_info), Options).

