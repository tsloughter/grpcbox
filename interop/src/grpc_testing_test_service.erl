-module(grpc_testing_test_service).

-behaviour(grpc_testing_test_service_bhvr).

-export([empty_call/2,
         unary_call/2,
         cacheable_unary_call/2,
         streaming_output_call/2,
         streaming_input_call/2,
         full_duplex_call/2,
         half_duplex_call/2]).

-include("grpcbox_interop_tests.hrl").

-spec empty_call(ctx:t(), test_pb:empty()) ->
                        {ok, test_pb:empty()} | grpcbox_stream:grpc_error_response().
empty_call(Ctx, _Empty) ->
    {ok, #{}, Ctx}.

-spec unary_call(ctx:t(), test_pb:simple_request()) ->
                        {ok, test_pb:simple_response()} | grpcbox_stream:grpc_error_response().
unary_call(Ctx, Request=#{response_size := Size}) ->
    case maps:get(response_status, Request, #{}) of
        #{code := Code,
          message := Message} ->
            {grpc_error, {grpcbox_stream:code_to_status(Code), Message}};
        _ ->
            Metadata = grpcbox_metadata:from_incoming_ctx(Ctx),
            EchoValue = maps:get(?INITIAL_METADATA_KEY, Metadata, <<>>),
            EchoTrailer = maps:get(?TRAILING_METADATA_KEY, Metadata, <<>>),
            Header = grpcbox_metadata:pairs([{?INITIAL_METADATA_KEY, EchoValue}]),
            grpcbox_stream:send_headers(Ctx, Header),
            Trailer = grpcbox_metadata:pairs([{?TRAILING_METADATA_KEY, EchoTrailer}]),
            Ctx1 = grpcbox_stream:set_trailers(Ctx, Trailer),

            Body = << <<0>> || _ <- lists:seq(1, Size) >>,
            {ok, #{payload => #{type => 'COMPRESSABLE',
                                body => Body
                               },
                   username => <<"tsloughter">>,
                   oauth_scope => <<"some-scope">>
                  }, Ctx1}
    end.

-spec cacheable_unary_call(ctx:t(), test_pb:simple_request()) ->
    {ok, test_pb:simple_response()} | grpcbox_stream:grpc_error_response().
cacheable_unary_call(Ctx, _SimpleRequest) ->
    {ok, #{}, Ctx}.

-spec streaming_output_call(test_pb:streaming_output_call_request(), grpcbox_stream:t()) ->
                                   ok | grpcbox_stream:grpc_error_response().
streaming_output_call(#{response_type := ResponseType,
                        response_parameters := ResponseParameters
                       }, Stream) ->
    lists:foreach(fun(#{size := Size,
                        interval_us := Interval}) ->
                          timer:sleep(erlang:convert_time_unit(Interval, microsecond, millisecond)),
                          Body = << <<0>> || _ <- lists:seq(1, Size) >>,
                          grpcbox_stream:send(#{payload => #{type => ResponseType,
                                                             body => Body}}, Stream)
                  end, ResponseParameters),
    ok.

-spec streaming_input_call(reference(), grpcbox_stream:t()) ->
                                  {ok, test_pb:streaming_input_call_response()} |
                                  grpcbox_stream:grpc_error_response().
streaming_input_call(Ref, GrpcStream) ->
    streaming_input_call(Ref, #{aggregated_payload_size => 0}, GrpcStream).

streaming_input_call(Ref, Data=#{aggregated_payload_size := Size}, GrpcStream) ->
    receive
        {Ref, eos} ->
            {ok, #{aggregated_payload_size => Size}, GrpcStream};
        {Ref, #{payload := #{type := _Type,
                             body := Body}}} ->
            streaming_input_call(Ref, Data#{aggregated_payload_size => Size + size(Body)}, GrpcStream)
    end.

-spec full_duplex_call(reference(), grpcbox_stream:t()) ->
                              ok | grpcbox_stream:grpc_error_response().
full_duplex_call(Ref, Stream) ->
    grpcbox_stream:add_headers([{?INITIAL_METADATA_KEY, ?INITIAL_METADATA_VALUE}], Stream),
    full_duplex_call_(Ref, Stream).

full_duplex_call_(Ref, Stream) ->
    receive
        {Ref, eos} ->
            grpcbox_stream:add_trailers([{?TRAILING_METADATA_KEY, ?TRAILING_METADATA_VALUE}], Stream),
            ok;
        {Ref, #{response_status := #{code := Code,
                                     message := Message}}} ->
            grpcbox_stream:error(grpcbox_stream:code_to_status(Code), Message);
        {Ref, #{response_type := ResponseType,
                response_parameters := ResponseParameters
               }} ->
            lists:foreach(fun(#{size := Size,
                                interval_us := Interval}) ->
                                  timer:sleep(erlang:convert_time_unit(Interval, microsecond, millisecond)),
                                  Body = << <<0>> || _ <- lists:seq(1, Size) >>,
                                  grpcbox_stream:send(#{payload => #{type => ResponseType,
                                                                     body => Body}}, Stream)
                          end, ResponseParameters),
            full_duplex_call_(Ref, Stream)
    end.

-spec half_duplex_call(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().
half_duplex_call(_Ref, _Stream) ->
    ok.

