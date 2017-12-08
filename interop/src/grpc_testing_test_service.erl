-module(grpc_testing_test_service).

-behaviour(grpc_testing_test_service_bhvr).

-export([empty_call/2,
         unary_call/2,
         cacheable_unary_call/2,
         streaming_output_call/2,
         streaming_input_call/2,
         full_duplex_call/2,
         half_duplex_call/2,
         unimplemented_call/2]).

-spec empty_call(ctx:ctx(), test_pb:'grpc.testing.Empty'()) ->
                        {ok, test_pb:'grpc.testing.Empty'()} | grpcbox_stream:grpc_error_response().
empty_call(Ctx, _Empty) ->
    {ok, #{}, Ctx}.

-spec unary_call(ctx:ctx(), test_pb:'grpc.testing.SimpleRequest'()) ->
                        {ok, test_pb:'grpc.testing.SimpleResponse'()} | grpcbox_stream:grpc_error_response().
unary_call(Ctx, #{response_size := Size}) ->
    Body = << <<0>> || _ <- lists:seq(1, Size) >>,
    {ok, #{payload => #{type => 'COMPRESSABLE',
                        body => Body
                       },
           username => <<"tsloughter">>,
           oauth_scope => <<"some-scope">>
          }, Ctx}.

-spec cacheable_unary_call(ctx:ctx(), test_pb:'grpc.testing.SimpleRequest'()) ->
    {ok, test_pb:'grpc.testing.SimpleResponse'()} | grpcbox_stream:grpc_error_response().
cacheable_unary_call(Ctx, _SimpleRequest) ->
    {ok, #{}, Ctx}.

-spec streaming_output_call(test_pb:'grpc.testing.StreamingOutputCallRequest'(), grpcbox_stream:t()) ->
                                   ok | grpcbox_stream:grpc_error_response().
streaming_output_call(#{response_type := ResponseType,
                        response_parameters := ResponseParameters,
                        payload := _Payload,
                        response_status := _Status
                       }, Stream) ->
    lists:foreach(fun(#{size := Size,
                        interval_us := _Interval,
                        compressed := _Compressed}) ->
                          Body = << <<0>> || _ <- lists:seq(1, Size) >>,
                          grpcbox_stream:send(#{payload => #{type => ResponseType,
                                                             body => Body}}, Stream)
                  end, ResponseParameters),
    ok.

-spec streaming_input_call(reference(), grpcbox_stream:t()) ->
                                  {ok, test_pb:'grpc.testing.StreamingInputCallResponse'()} |
                                  grpcbox_stream:grpc_error_response().
streaming_input_call(Ref, GrpcStream) ->
    streaming_input_call(Ref, #{aggregated_payload_size => 0}, GrpcStream).

streaming_input_call(Ref, Data=#{aggregated_payload_size := Size}, GrpcStream) ->
    receive
        {Ref, eos} ->
            {ok, #{aggregated_payload_size => Size}, GrpcStream};
        {Ref, #{payload := #{type := _Type,
                             body := Body},
                expect_compressed := _Compressed}} ->
            streaming_input_call(Ref, Data#{aggregated_payload_size => Size + size(Body)}, GrpcStream)
    end.

-spec full_duplex_call(reference(), grpcbox_stream:t()) ->
                              ok | grpcbox_stream:grpc_error_response().
full_duplex_call(Ref, Stream) ->
    receive
        {Ref, eos} ->
            ok;
        {Ref, #{response_type := ResponseType,
                response_parameters := ResponseParameters,
                payload := _Payload,
                response_status := _Status
               }} ->
            lists:foreach(fun(#{size := Size,
                                interval_us := _Interval,
                                compressed := _Compressed}) ->
                                  Body = << <<0>> || _ <- lists:seq(1, Size) >>,
                                  grpcbox_stream:send(#{payload => #{type => ResponseType,
                                                                     body => Body}}, Stream)
                          end, ResponseParameters),
            full_duplex_call(Ref, Stream)
    end.

-spec half_duplex_call(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().
half_duplex_call(_Ref, _Stream) ->
    ok.

-spec unimplemented_call(ctx:ctx(), test_pb:'grpc.testing.Empty'()) ->
    {ok, test_pb:'grpc.testing.Empty'()} | grpcbox_stream:grpc_error_response().
unimplemented_call(Ctx, _Empty) ->
    {ok, #{}, Ctx}.
