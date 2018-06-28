%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.testing.TestService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2018-06-28T22:22:37+00:00 and should not be modified manually

-module(grpc_testing_test_service_client).

-compile([nowarn_export_all]).
-compile([export_all]).

-include("grpcbox.hrl").

-define(SERVICE, 'grpc.testing.TestService').
-define(PROTO_MODULE, 'test_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output), #grpcbox_def{service=?SERVICE,
                                         marshal_fun=?MARSHAL_FUN(Input),
                                         unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc Unary RPC
-spec empty_call(ctx:t(), test_pb:empty()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
empty_call(Ctx, Input) ->
    empty_call(Ctx, Input, #{}).

-spec empty_call(ctx:t(), test_pb:empty(), grpcbox_client:options()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
empty_call(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.TestService/EmptyCall">>, Input, ?DEF(empty, empty), Options).

%% @doc Unary RPC
-spec unary_call(ctx:t(), test_pb:simple_request()) ->
    {ok, test_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unary_call(Ctx, Input) ->
    unary_call(Ctx, Input, #{}).

-spec unary_call(ctx:t(), test_pb:simple_request(), grpcbox_client:options()) ->
    {ok, test_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unary_call(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.TestService/UnaryCall">>, Input, ?DEF(simple_request, simple_response), Options).

%% @doc Unary RPC
-spec cacheable_unary_call(ctx:t(), test_pb:simple_request()) ->
    {ok, test_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
cacheable_unary_call(Ctx, Input) ->
    cacheable_unary_call(Ctx, Input, #{}).

-spec cacheable_unary_call(ctx:t(), test_pb:simple_request(), grpcbox_client:options()) ->
    {ok, test_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
cacheable_unary_call(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.TestService/CacheableUnaryCall">>, Input, ?DEF(simple_request, simple_response), Options).

%% @doc 
-spec streaming_output_call(ctx:t(), test_pb:streaming_output_call_request()) ->
    {ok, grpcbox_stream:t()} | grpcbox_stream:grpc_error_response().
streaming_output_call(Ctx, Input) ->
    streaming_output_call(Ctx, Input, #{}).

-spec streaming_output_call(ctx:t(), test_pb:streaming_output_call_request(), grpcbox_client:options()) ->
    {ok, grpcbox_stream:t()} | grpcbox_stream:grpc_error_response().
streaming_output_call(Ctx, Input, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.TestService/StreamingOutputCall">>, Input, ?DEF(streaming_output_call_request, streaming_output_call_response), Options).

%% @doc 
-spec streaming_input_call(ctx:t()) ->
    {ok, grpcbox_stream:t()} | grpcbox_stream:grpc_error_response().
streaming_input_call(Ctx) ->
    streaming_input_call(Ctx, #{}).

-spec streaming_input_call(ctx:t(), grpcbox_client:options()) ->
    {ok, grpcbox_stream:t()} | grpcbox_stream:grpc_error_response().
streaming_input_call(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.TestService/StreamingInputCall">>, ?DEF(streaming_input_call_request, streaming_input_call_response), Options).

%% @doc 
-spec full_duplex_call(ctx:t()) ->
    {ok, grpclient:stream()} | grpcbox_stream:grpc_error_response().
full_duplex_call(Ctx) ->
    full_duplex_call(Ctx, #{}).

-spec full_duplex_call(ctx:t(), grpcbox_client:options()) ->
    {ok, grpclient:stream()} | grpcbox_stream:grpc_error_response().
full_duplex_call(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.TestService/FullDuplexCall">>, ?DEF(streaming_output_call_request, streaming_output_call_response), Options).

%% @doc 
-spec half_duplex_call(ctx:t()) ->
    {ok, grpclient:stream()} | grpcbox_stream:grpc_error_response().
half_duplex_call(Ctx) ->
    half_duplex_call(Ctx, #{}).

-spec half_duplex_call(ctx:t(), grpcbox_client:options()) ->
    {ok, grpclient:stream()} | grpcbox_stream:grpc_error_response().
half_duplex_call(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.TestService/HalfDuplexCall">>, ?DEF(streaming_output_call_request, streaming_output_call_response), Options).

%% @doc Unary RPC
-spec unimplemented_call(ctx:t(), test_pb:empty()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unimplemented_call(Ctx, Input) ->
    unimplemented_call(Ctx, Input, #{}).

-spec unimplemented_call(ctx:t(), test_pb:empty(), grpcbox_client:options()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unimplemented_call(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.TestService/UnimplementedCall">>, Input, ?DEF(empty, empty), Options).

