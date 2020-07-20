-module(grpcbox_interop_client_SUITE).

-compile([export_all]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").
-include("grpcbox_interop_tests.hrl").

-include("grpcbox.hrl").

-define(REQ_SIZES, [27182, 8, 1828, 45904]).
-define(RESP_SIZES, [31415, 9, 2653, 58979]).

all() ->
    [{group, identity},
     {group, gzip}
    ].

groups() ->
    Cases = [empty_unary, large_unary, client_streaming, server_streaming,
             ping_pong, empty_stream, status_code_and_message, custom_metadata,
             unimplemented_method, unimplemented_service],
    [{identity, Cases},
     {gzip, Cases}
    ].

init_per_group(Encoding, Config) ->
    application:load(grpcbox),
    application:set_env(grpcbox, client, #{channels => [{default_channel, [{http, "localhost", 8080, []}],
                                                         #{encoding => Encoding}}]}),
    {ok, _} = application:ensure_all_started(grpcbox),
    Config.

end_per_group(_Encoding, _Config) ->
    application:stop(grpcbox),
    ok.

empty_unary(_Config) ->
    ?assertMatch({ok, _, _}, grpc_testing_test_service_client:empty_call(ctx:new(), #{})).

large_unary(_Config) ->
    Payload = client_payload(271828),
    SimpleRequest = #{payload => Payload},
    ?assertMatch({ok, _, _}, grpc_testing_test_service_client:unary_call(ctx:new(), SimpleRequest)).

client_streaming(_Config) ->
    TotalSize = lists:sum(?REQ_SIZES),

    {ok, S} = grpc_testing_test_service_client:streaming_input_call(ctx:new()),
    lists:foreach(fun(Size) ->
                          ReqPayload = client_payload(Size),
                          ok = grpcbox_client:send(S, #{payload => ReqPayload})
                  end, ?REQ_SIZES),

    %% server returns the total aggregated payload size
    ?assertMatch({ok, #{aggregated_payload_size := TotalSize}}, grpcbox_client:close_and_recv(S)).

server_streaming(_Config) ->
    RespSizes = [31415, 9, 2653, 58979],
    Payload = #{response_parameters => [#{size => S} || S <- RespSizes]},
    {ok, S} = grpc_testing_test_service_client:streaming_output_call(ctx:new(), Payload),

    lists:foreach(fun(Size) ->
                          {ok, #{payload := #{body := Body1}}} = grpcbox_client:recv_data(S),
                          ?assertMatch(Size, erlang:byte_size(Body1))
                  end, RespSizes).

ping_pong(_Config) ->
    Sizes = lists:zip(?REQ_SIZES, ?RESP_SIZES),
    {ok, S} = grpc_testing_test_service_client:full_duplex_call(ctx:new()),
    lists:foreach(fun({ReqSize, RespSize}) ->
                          Payload = client_payload(ReqSize),
                          Req = #{response_parameters => [#{size => RespSize}],
                                  payload => Payload},
                          ok = grpcbox_client:send(S, Req),

                          {ok, #{payload := #{body := Body1}}} = grpcbox_client:recv_data(S),
                          ?assertMatch(RespSize, erlang:byte_size(Body1))
                  end, Sizes).

empty_stream(_Config) ->
    {ok, S} = grpc_testing_test_service_client:full_duplex_call(ctx:new()),
    ok = grpcbox_client:close_send(S),
    ?assertMatch(stream_finished, grpcbox_client:recv_data(S)).

status_code_and_message(_Config) ->
    Msg = <<"test status message">>,
    RespStatus = #{code => 2,
                   message => Msg},
    Req = #{response_status => RespStatus},

    ?assertMatch({error, {<<"2">>, Msg}, _}, grpc_testing_test_service_client:unary_call(ctx:new(), Req)).

custom_metadata(_Config) ->
    Payload = client_payload(1),
    SimpleRequest = #{response_size => 1,
                      payload => Payload},

    Metadata = grpcbox_metadata:pairs([{?INITIAL_METADATA_KEY, ?INITIAL_METADATA_VALUE},
                                       {?TRAILING_METADATA_KEY, ?TRAILING_METADATA_VALUE}]),
    Ctx = grpcbox_metadata:append_to_outgoing_ctx(ctx:new(), Metadata),
    {ok, _, #{headers := Headers,
              trailers := Trailers}} = grpc_testing_test_service_client:unary_call(Ctx, SimpleRequest),

    ?assertEqual(?INITIAL_METADATA_VALUE, maps:get(?INITIAL_METADATA_KEY, Headers)),
    ?assertEqual(?TRAILING_METADATA_VALUE, maps:get(?TRAILING_METADATA_KEY, Trailers)),

    %% test also with full duplex

    {ok, S} = grpc_testing_test_service_client:full_duplex_call(Ctx),
    Req = #{response_parameters => [#{size => 1}],
            payload => Payload},
    ok = grpcbox_client:send(S, Req),

    {ok, #{payload := #{body := Body1}}} = grpcbox_client:recv_data(S),
    ?assertMatch(1, erlang:byte_size(Body1)),

    grpcbox_client:close_send(S),
    {ok, Headers1} = grpcbox_client:recv_headers(S),
    {ok, {_, _, Trailers1}} = grpcbox_client:recv_trailers(S),
    ?assertEqual(?INITIAL_METADATA_VALUE, maps:get(?INITIAL_METADATA_KEY, Headers1)),
    ?assertEqual(?TRAILING_METADATA_VALUE, maps:get(?TRAILING_METADATA_KEY, Trailers1)).

unimplemented_method(_Config) ->
    Def = #grpcbox_def{service = 'grpc.testing.TestService',
                       marshal_fun = fun(I) -> test_pb:encode_msg(I, simple_request) end,
                       unmarshal_fun = fun(I) -> test_pb:encode_msg(I, simple_response) end},
    ?assertMatch({error, {?GRPC_STATUS_UNIMPLEMENTED, _}, _},
                 grpcbox_client:unary(ctx:new(), <<"/grpc.testing.TestService/NotReal">>, #{}, Def, #{})).

unimplemented_service(_Config) ->
    Def = #grpcbox_def{service = 'grpc.testing.Unimplemented',
                       marshal_fun = fun(I) -> test_pb:encode_msg(I, simple_request) end,
                       unmarshal_fun = fun(I) -> test_pb:encode_msg(I, simple_response) end},
    ?assertMatch({error, {?GRPC_STATUS_UNIMPLEMENTED, _}, _},
                 grpcbox_client:unary(ctx:new(), <<"/grpc.testing.Unimplemented/NotReal">>, #{}, Def, #{})).

client_payload(NumBytes) ->
    Body = << <<0:8>> || _ <- lists:seq(1, NumBytes)>>,
    #{type => 0,
      body => Body}.
