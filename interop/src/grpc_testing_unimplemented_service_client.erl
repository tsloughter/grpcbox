%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.testing.UnimplementedService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2018-06-28T22:22:37+00:00 and should not be modified manually

-module(grpc_testing_unimplemented_service_client).

-compile([nowarn_export_all]).
-compile([export_all]).

-include("grpcbox.hrl").

-define(SERVICE, 'grpc.testing.UnimplementedService').
-define(PROTO_MODULE, 'test_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output), #grpcbox_def{service=?SERVICE,
                                         marshal_fun=?MARSHAL_FUN(Input),
                                         unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc Unary RPC
-spec unimplemented_call(ctx:t(), test_pb:empty()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unimplemented_call(Ctx, Input) ->
    unimplemented_call(Ctx, Input, #{}).

-spec unimplemented_call(ctx:t(), test_pb:empty(), grpcbox_client:options()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unimplemented_call(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.UnimplementedService/UnimplementedCall">>, Input, ?DEF(empty, empty), Options).

