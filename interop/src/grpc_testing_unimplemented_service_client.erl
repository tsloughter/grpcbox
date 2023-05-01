%%%-------------------------------------------------------------------
%% @doc Client module for grpc service grpc.testing.UnimplementedService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-03-09T00:28:54+00:00 and should not be modified manually

-module(grpc_testing_unimplemented_service_client).

-compile(export_all).
-compile(nowarn_export_all).

-include("grpcbox.hrl").

-define(is_ctx(Ctx), is_tuple(Ctx) andalso element(1, Ctx) =:= ctx).

-define(SERVICE, 'grpc.testing.UnimplementedService').
-define(PROTO_MODULE, 'test_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output, MessageType), #grpcbox_def{service=?SERVICE,
                                                      message_type=MessageType,
                                                      marshal_fun=?MARSHAL_FUN(Input),
                                                      unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc Unary RPC
-spec unimplemented_call(test_pb:empty()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unimplemented_call(Input) ->
    unimplemented_call(ctx:new(), Input, #{}).

-spec unimplemented_call(ctx:t() | test_pb:empty(), test_pb:empty() | grpcbox_client:options()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unimplemented_call(Ctx, Input) when ?is_ctx(Ctx) ->
    unimplemented_call(Ctx, Input, #{});
unimplemented_call(Input, Options) ->
    unimplemented_call(ctx:new(), Input, Options).

-spec unimplemented_call(ctx:t(), test_pb:empty(), grpcbox_client:options()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unimplemented_call(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.UnimplementedService/UnimplementedCall">>, Input, ?DEF(empty, empty, <<"grpc.testing.Empty">>), Options).

