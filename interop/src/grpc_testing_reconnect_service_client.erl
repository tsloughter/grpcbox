%%%-------------------------------------------------------------------
%% @doc Client module for grpc service grpc.testing.ReconnectService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-03-09T00:28:54+00:00 and should not be modified manually

-module(grpc_testing_reconnect_service_client).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("grpcbox/include/grpcbox.hrl").

-define(is_ctx(Ctx), is_tuple(Ctx) andalso element(1, Ctx) =:= ctx).

-define(SERVICE, 'grpc.testing.ReconnectService').
-define(PROTO_MODULE, 'test_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output, MessageType), #grpcbox_def{service=?SERVICE,
                                                      message_type=MessageType,
                                                      marshal_fun=?MARSHAL_FUN(Input),
                                                      unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc Unary RPC
-spec start(test_pb:reconnect_params()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
start(Input) ->
    start(ctx:new(), Input, #{}).

-spec start(ctx:t() | test_pb:reconnect_params(), test_pb:reconnect_params() | grpcbox_client:options()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
start(Ctx, Input) when ?is_ctx(Ctx) ->
    start(Ctx, Input, #{});
start(Input, Options) ->
    start(ctx:new(), Input, Options).

-spec start(ctx:t(), test_pb:reconnect_params(), grpcbox_client:options()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
start(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.ReconnectService/Start">>, Input, ?DEF(reconnect_params, empty, <<"grpc.testing.ReconnectParams">>), Options).

%% @doc Unary RPC
-spec stop(test_pb:empty()) ->
    {ok, test_pb:reconnect_info(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
stop(Input) ->
    stop(ctx:new(), Input, #{}).

-spec stop(ctx:t() | test_pb:empty(), test_pb:empty() | grpcbox_client:options()) ->
    {ok, test_pb:reconnect_info(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
stop(Ctx, Input) when ?is_ctx(Ctx) ->
    stop(Ctx, Input, #{});
stop(Input, Options) ->
    stop(ctx:new(), Input, Options).

-spec stop(ctx:t(), test_pb:empty(), grpcbox_client:options()) ->
    {ok, test_pb:reconnect_info(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
stop(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.ReconnectService/Stop">>, Input, ?DEF(empty, reconnect_info, <<"grpc.testing.Empty">>), Options).

