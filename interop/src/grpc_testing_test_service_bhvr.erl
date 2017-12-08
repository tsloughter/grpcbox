%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.testing.TestService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2017-12-08T01:24:35+00:00 and should not be modified manually

-module(grpc_testing_test_service_bhvr).

%% @doc Unary RPC
-callback empty_call(ctx:ctx(), test_pb:'grpc.testing.Empty'()) ->
    {ok, test_pb:'grpc.testing.Empty'()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback unary_call(ctx:ctx(), test_pb:'grpc.testing.SimpleRequest'()) ->
    {ok, test_pb:'grpc.testing.SimpleResponse'()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback cacheable_unary_call(ctx:ctx(), test_pb:'grpc.testing.SimpleRequest'()) ->
    {ok, test_pb:'grpc.testing.SimpleResponse'()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback streaming_output_call(test_pb:'grpc.testing.StreamingOutputCallRequest'(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

%% @doc 
-callback streaming_input_call(reference(), grpcbox_stream:t()) ->
    {ok, test_pb:'grpc.testing.StreamingInputCallResponse'()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback full_duplex_call(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

%% @doc 
-callback half_duplex_call(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback unimplemented_call(ctx:ctx(), test_pb:'grpc.testing.Empty'()) ->
    {ok, test_pb:'grpc.testing.Empty'()} | grpcbox_stream:grpc_error_response().

