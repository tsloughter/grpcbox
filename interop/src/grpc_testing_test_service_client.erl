%%%-------------------------------------------------------------------
%% @doc Client module for grpc service grpc.testing.TestService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-03-09T00:28:54+00:00 and should not be modified manually

-module(grpc_testing_test_service_client).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("grpcbox/include/grpcbox.hrl").

-define(is_ctx(Ctx), is_tuple(Ctx) andalso element(1, Ctx) =:= ctx).

-define(SERVICE, 'grpc.testing.TestService').
-define(PROTO_MODULE, 'test_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output, MessageType), #grpcbox_def{service=?SERVICE,
                                                      message_type=MessageType,
                                                      marshal_fun=?MARSHAL_FUN(Input),
                                                      unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc Unary RPC
-spec empty_call(test_pb:empty()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
empty_call(Input) ->
    empty_call(ctx:new(), Input, #{}).

-spec empty_call(ctx:t() | test_pb:empty(), test_pb:empty() | grpcbox_client:options()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
empty_call(Ctx, Input) when ?is_ctx(Ctx) ->
    empty_call(Ctx, Input, #{});
empty_call(Input, Options) ->
    empty_call(ctx:new(), Input, Options).

-spec empty_call(ctx:t(), test_pb:empty(), grpcbox_client:options()) ->
    {ok, test_pb:empty(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
empty_call(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.TestService/EmptyCall">>, Input, ?DEF(empty, empty, <<"grpc.testing.Empty">>), Options).

%% @doc Unary RPC
-spec unary_call(test_pb:simple_request()) ->
    {ok, test_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unary_call(Input) ->
    unary_call(ctx:new(), Input, #{}).

-spec unary_call(ctx:t() | test_pb:simple_request(), test_pb:simple_request() | grpcbox_client:options()) ->
    {ok, test_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unary_call(Ctx, Input) when ?is_ctx(Ctx) ->
    unary_call(Ctx, Input, #{});
unary_call(Input, Options) ->
    unary_call(ctx:new(), Input, Options).

-spec unary_call(ctx:t(), test_pb:simple_request(), grpcbox_client:options()) ->
    {ok, test_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unary_call(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.TestService/UnaryCall">>, Input, ?DEF(simple_request, simple_response, <<"grpc.testing.SimpleRequest">>), Options).

%% @doc Unary RPC
-spec cacheable_unary_call(test_pb:simple_request()) ->
    {ok, test_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
cacheable_unary_call(Input) ->
    cacheable_unary_call(ctx:new(), Input, #{}).

-spec cacheable_unary_call(ctx:t() | test_pb:simple_request(), test_pb:simple_request() | grpcbox_client:options()) ->
    {ok, test_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
cacheable_unary_call(Ctx, Input) when ?is_ctx(Ctx) ->
    cacheable_unary_call(Ctx, Input, #{});
cacheable_unary_call(Input, Options) ->
    cacheable_unary_call(ctx:new(), Input, Options).

-spec cacheable_unary_call(ctx:t(), test_pb:simple_request(), grpcbox_client:options()) ->
    {ok, test_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
cacheable_unary_call(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.TestService/CacheableUnaryCall">>, Input, ?DEF(simple_request, simple_response, <<"grpc.testing.SimpleRequest">>), Options).

%% @doc 
-spec streaming_output_call(test_pb:streaming_output_call_request()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_output_call(Input) ->
    streaming_output_call(ctx:new(), Input, #{}).

-spec streaming_output_call(ctx:t() | test_pb:streaming_output_call_request(), test_pb:streaming_output_call_request() | grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_output_call(Ctx, Input) when ?is_ctx(Ctx) ->
    streaming_output_call(Ctx, Input, #{});
streaming_output_call(Input, Options) ->
    streaming_output_call(ctx:new(), Input, Options).

-spec streaming_output_call(ctx:t(), test_pb:streaming_output_call_request(), grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_output_call(Ctx, Input, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.TestService/StreamingOutputCall">>, Input, ?DEF(streaming_output_call_request, streaming_output_call_response, <<"grpc.testing.StreamingOutputCallRequest">>), Options).

%% @doc 
-spec streaming_input_call() ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_input_call() ->
    streaming_input_call(ctx:new(), #{}).

-spec streaming_input_call(ctx:t() | grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_input_call(Ctx) when ?is_ctx(Ctx) ->
    streaming_input_call(Ctx, #{});
streaming_input_call(Options) ->
    streaming_input_call(ctx:new(), Options).

-spec streaming_input_call(ctx:t(), grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_input_call(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.TestService/StreamingInputCall">>, ?DEF(streaming_input_call_request, streaming_input_call_response, <<"grpc.testing.StreamingInputCallRequest">>), Options).

%% @doc 
-spec full_duplex_call() ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
full_duplex_call() ->
    full_duplex_call(ctx:new(), #{}).

-spec full_duplex_call(ctx:t() | grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
full_duplex_call(Ctx) when ?is_ctx(Ctx) ->
    full_duplex_call(Ctx, #{});
full_duplex_call(Options) ->
    full_duplex_call(ctx:new(), Options).

-spec full_duplex_call(ctx:t(), grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
full_duplex_call(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.TestService/FullDuplexCall">>, ?DEF(streaming_output_call_request, streaming_output_call_response, <<"grpc.testing.StreamingOutputCallRequest">>), Options).

%% @doc 
-spec half_duplex_call() ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
half_duplex_call() ->
    half_duplex_call(ctx:new(), #{}).

-spec half_duplex_call(ctx:t() | grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
half_duplex_call(Ctx) when ?is_ctx(Ctx) ->
    half_duplex_call(Ctx, #{});
half_duplex_call(Options) ->
    half_duplex_call(ctx:new(), Options).

-spec half_duplex_call(ctx:t(), grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
half_duplex_call(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.TestService/HalfDuplexCall">>, ?DEF(streaming_output_call_request, streaming_output_call_response, <<"grpc.testing.StreamingOutputCallRequest">>), Options).

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
    grpcbox_client:unary(Ctx, <<"/grpc.testing.TestService/UnimplementedCall">>, Input, ?DEF(empty, empty, <<"grpc.testing.Empty">>), Options).

