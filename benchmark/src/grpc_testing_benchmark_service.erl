-module(grpc_testing_benchmark_service).

-behaviour(grpc_testing_benchmark_service_bhvr).

-export([unary_call/2,
         streaming_call/2,
         streaming_from_client/2,
         streaming_from_server/2,
         streaming_both_ways/2]).

-spec unary_call(ctx:ctx(), benchmark_service_pb:simple_request()) ->
                        {ok, benchmark_service_pb:simple_response()} | grpcbox_stream:grpc_error_response().
unary_call(Ctx, #{response_size := Size}) ->
    Body = << <<0>> || _ <- lists:seq(1, Size) >>,
    {ok, #{payload => #{type => 'COMPRESSABLE',
                        body => Body
                       }
          }, Ctx}.

-spec streaming_call(reference(), grpcbox_stream:t()) ->
          ok | grpcbox_stream:grpc_error_response().
streaming_call(Ref, Stream) ->
    receive
        {Ref, eos} ->
            ok;
        {Ref, #{response_status := #{code := Code,
                                     message := Message}}} ->
            grpcbox_stream:error(grpcbox_stream:code_to_status(Code), Message);
        {Ref, #{response_type := ResponseType,
                response_size := ResponseSize
               }} ->
            Body = << <<0>> || _ <- lists:seq(1, ResponseSize) >>,
            grpcbox_stream:send(#{payload => #{type => ResponseType,
                                               body => Body}}, Stream),
            streaming_call(Ref, Stream)
    end.

-spec streaming_from_client(reference(), grpcbox_stream:t()) ->
    {ok, benchmark_service_pb:simple_response(), ctx:ctx()} | grpcbox_stream:grpc_error_response().
streaming_from_client(_Ref, _Stream) ->
    ok.

-spec streaming_from_server(benchmark_service_pb:simple_request(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().
streaming_from_server(_Ref, _Stream) ->
    ok.

-spec streaming_both_ways(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().
streaming_both_ways(_Ref, _Stream) ->
    ok.
