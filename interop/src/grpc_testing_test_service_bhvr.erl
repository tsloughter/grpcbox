%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.testing.TestService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-03-09T00:28:54+00:00 and should not be modified manually

-module(grpc_testing_test_service_bhvr).

%% @doc Unary RPC
-callback empty_call(ctx:t(), test_pb:empty()) ->
    {ok, test_pb:empty(), ctx:t()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback unary_call(ctx:t(), test_pb:simple_request()) ->
    {ok, test_pb:simple_response(), ctx:t()} | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback cacheable_unary_call(ctx:t(), test_pb:simple_request()) ->
    {ok, test_pb:simple_response(), ctx:t()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback streaming_output_call(test_pb:streaming_output_call_request(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

%% @doc 
-callback streaming_input_call(reference(), grpcbox_stream:t()) ->
    {ok, test_pb:streaming_input_call_response(), ctx:t()} | grpcbox_stream:grpc_error_response().

%% @doc 
-callback full_duplex_call(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

%% @doc 
-callback half_duplex_call(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

%% @doc Unary RPC
-callback unimplemented_call(ctx:t(), test_pb:empty()) ->
    {ok, test_pb:empty(), ctx:t()} | grpcbox_stream:grpc_error_response().

