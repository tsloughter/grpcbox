%%%-------------------------------------------------------------------
%% @doc Client module for grpc service grpc.reflection.v1alpha.ServerReflection.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-01-19T16:04:23+00:00 and should not be modified manually

-module(grpcbox_reflection_client).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("grpcbox/include/grpcbox.hrl").

-define(SERVICE, 'grpc.reflection.v1alpha.ServerReflection').
-define(PROTO_MODULE, 'grpcbox_reflection_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output), #grpcbox_def{service=?SERVICE,
                                         marshal_fun=?MARSHAL_FUN(Input),
                                         unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc 
-spec server_reflection_info(ctx:t()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
server_reflection_info(Ctx) ->
    server_reflection_info(Ctx, #{}).

-spec server_reflection_info(ctx:t(), grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
server_reflection_info(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.reflection.v1alpha.ServerReflection/ServerReflectionInfo">>, ?DEF(server_reflection_request, server_reflection_response), Options).

