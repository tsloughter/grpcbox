%%%-------------------------------------------------------------------
%% @doc Client module for grpc service grpc.testing.BenchmarkService.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2021-12-29T09:28:22+00:00 and should not be modified manually

-module(grpc_testing_benchmark_service_client).

-compile(export_all).
-compile(nowarn_export_all).

-include_lib("grpcbox/include/grpcbox.hrl").

-define(is_ctx(Ctx), is_tuple(Ctx) andalso element(1, Ctx) =:= ctx).

-define(SERVICE, 'grpc.testing.BenchmarkService').
-define(PROTO_MODULE, 'benchmark_service_pb').
-define(MARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:encode_msg(I, T) end).
-define(UNMARSHAL_FUN(T), fun(I) -> ?PROTO_MODULE:decode_msg(I, T) end).
-define(DEF(Input, Output, MessageType), #grpcbox_def{service=?SERVICE,
                                                      message_type=MessageType,
                                                      marshal_fun=?MARSHAL_FUN(Input),
                                                      unmarshal_fun=?UNMARSHAL_FUN(Output)}).

%% @doc Unary RPC
-spec unary_call(benchmark_service_pb:simple_request()) ->
    {ok, benchmark_service_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unary_call(Input) ->
    unary_call(ctx:new(), Input, #{}).

-spec unary_call(ctx:t() | benchmark_service_pb:simple_request(), benchmark_service_pb:simple_request() | grpcbox_client:options()) ->
    {ok, benchmark_service_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unary_call(Ctx, Input) when ?is_ctx(Ctx) ->
    unary_call(Ctx, Input, #{});
unary_call(Input, Options) ->
    unary_call(ctx:new(), Input, Options).

-spec unary_call(ctx:t(), benchmark_service_pb:simple_request(), grpcbox_client:options()) ->
    {ok, benchmark_service_pb:simple_response(), grpcbox:metadata()} | grpcbox_stream:grpc_error_response().
unary_call(Ctx, Input, Options) ->
    grpcbox_client:unary(Ctx, <<"/grpc.testing.BenchmarkService/UnaryCall">>, Input, ?DEF(simple_request, simple_response, <<"grpc.testing.SimpleRequest">>), Options).

%% @doc 
-spec streaming_call() ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_call() ->
    streaming_call(ctx:new(), #{}).

-spec streaming_call(ctx:t() | grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_call(Ctx) when ?is_ctx(Ctx) ->
    streaming_call(Ctx, #{});
streaming_call(Options) ->
    streaming_call(ctx:new(), Options).

-spec streaming_call(ctx:t(), grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_call(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.BenchmarkService/StreamingCall">>, ?DEF(simple_request, simple_response, <<"grpc.testing.SimpleRequest">>), Options).

%% @doc 
-spec streaming_from_client() ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_from_client() ->
    streaming_from_client(ctx:new(), #{}).

-spec streaming_from_client(ctx:t() | grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_from_client(Ctx) when ?is_ctx(Ctx) ->
    streaming_from_client(Ctx, #{});
streaming_from_client(Options) ->
    streaming_from_client(ctx:new(), Options).

-spec streaming_from_client(ctx:t(), grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_from_client(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.BenchmarkService/StreamingFromClient">>, ?DEF(simple_request, simple_response, <<"grpc.testing.SimpleRequest">>), Options).

%% @doc 
-spec streaming_from_server(benchmark_service_pb:simple_request()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_from_server(Input) ->
    streaming_from_server(ctx:new(), Input, #{}).

-spec streaming_from_server(ctx:t() | benchmark_service_pb:simple_request(), benchmark_service_pb:simple_request() | grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_from_server(Ctx, Input) when ?is_ctx(Ctx) ->
    streaming_from_server(Ctx, Input, #{});
streaming_from_server(Input, Options) ->
    streaming_from_server(ctx:new(), Input, Options).

-spec streaming_from_server(ctx:t(), benchmark_service_pb:simple_request(), grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_from_server(Ctx, Input, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.BenchmarkService/StreamingFromServer">>, Input, ?DEF(simple_request, simple_response, <<"grpc.testing.SimpleRequest">>), Options).

%% @doc 
-spec streaming_both_ways() ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_both_ways() ->
    streaming_both_ways(ctx:new(), #{}).

-spec streaming_both_ways(ctx:t() | grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_both_ways(Ctx) when ?is_ctx(Ctx) ->
    streaming_both_ways(Ctx, #{});
streaming_both_ways(Options) ->
    streaming_both_ways(ctx:new(), Options).

-spec streaming_both_ways(ctx:t(), grpcbox_client:options()) ->
    {ok, grpcbox_client:stream()} | grpcbox_stream:grpc_error_response().
streaming_both_ways(Ctx, Options) ->
    grpcbox_client:stream(Ctx, <<"/grpc.testing.BenchmarkService/StreamingBothWays">>, ?DEF(simple_request, simple_response, <<"grpc.testing.SimpleRequest">>), Options).

