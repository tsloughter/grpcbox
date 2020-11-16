-module(grpcbox_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-include_lib("opencensus/include/opencensus.hrl").

-include("grpcbox.hrl").

groups() ->
    [{ssl, [], [unary_authenticated]},
     {tcp, [], [unary_no_auth, multiple_servers]},
     {negative_tests, [], [unimplemented, closed_stream, generate_error, streaming_generate_error]},
     {negative_ssl, [], [unauthorized]},
     {context, [], [%% deadline
                   ]}].

all() ->
    [{group, ssl},
     {group, tcp},
     {group, negative_tests},
     {group, negative_ssl},
     initially_down_service,
     unary_interceptor,
     unary_client_interceptor,
     chain_interceptor,
     stream_interceptor,
     bidirectional,
     stress_test,
     client_stream,
     compression,
     stats_handler,
     health_service,
     reflection_service
     %% TODO: rst stream error handling
     %% %% trace_interceptor
    ].

init_per_suite(Config) ->
    application:load(grpcbox),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(ssl, Config) ->
    ClientCerts = cert_dir(Config),
    Options = [{certfile, cert(Config, "server1.pem")},
               {keyfile, cert(Config, "server1.key")},
               {cacertfile, cert(Config, "ca.pem")}
              ],
    application:set_env(grpcbox, client, #{channels => [{default_channel, [{https, "localhost", 8080, Options}], #{}}]}),
    Servers = [#{grpc_opts => #{service_protos => [route_guide_pb],
                                services => #{'routeguide.RouteGuide' => routeguide_route_guide},
                                client_cert_dir => ClientCerts},
                 transport_opts => #{ssl => true,
                                     keyfile => cert(Config, "server1.key"),
                                     certfile => cert(Config, "server1.pem"),
                                     cacertfile => cert(Config, "ca.pem")}}],
    application:set_env(grpcbox, servers, Servers),
    application:ensure_all_started(grpcbox),
    Config;
init_per_group(tcp, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel, [{http, "localhost", 8080, []}],
                                                         #{}}]}),
    application:set_env(grpcbox, servers, [#{grpc_opts => #{service_protos => [route_guide_pb],
                                                            services => #{'routeguide.RouteGuide' =>
                                                                              routeguide_route_guide}},
                                             transport_opts => #{}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_group(negative_tests, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel, [{http, "localhost", 8080, []}], #{}}]}),
    application:set_env(grpcbox, servers, [#{grpc_opts => #{service_protos => [route_guide_pb],
                                                            services => #{'routeguide.RouteGuide' =>
                                                                              routeguide_route_guide}},
                                             transport_opts => #{}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_group(negative_ssl, Config) ->
    ClientCerts = cert_dir(Config),
    Options = [{certfile, cert(Config, "server1.pem")},
               {keyfile, cert(Config, "server1.key")},
               {cacertfile, cert(Config, "ca.pem")}],
    application:set_env(grpcbox, client, #{channels => [{default_channel, [{https, "localhost", 8080, Options}], #{}}]}),

    Servers = [#{grpc_opts => #{service_protos => [route_guide_pb],
                                services => #{'routeguide.RouteGuide' => routeguide_route_guide},
                                client_cert_dir => ClientCerts,
                                auth_fun => fun(_) -> false end
                               },
                 transport_opts => #{ssl => true,
                                     keyfile => cert(Config, "server1.key"),
                                     certfile => cert(Config, "server1.pem"),
                                     cacertfile => cert(Config, "ca.pem")}}],
    application:set_env(grpcbox, servers, Servers),
    application:ensure_all_started(grpcbox),
    Config.

end_per_group(_, _Config) ->
    ?assertMatch(ok, grpcbox_services_simple_sup:terminate_child(#{ip => {0, 0, 0, 0},
                                                                   port => 8080})),
    application:stop(grpcbox),
    ok.

init_per_testcase(initially_down_service, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}], #{}}]}),
    application:set_env(grpcbox, servers, []),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(unary_client_interceptor, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}],
                                                         #{unary_interceptor => fun(Ctx, _Channel, Handler, _Path, _Input, _Def, _Options) ->
                                                                                        Handler(Ctx, #{latitude => 30,
                                                                                                       longitude => 90})
                                                                                end}}]}),
    application:set_env(grpcbox, servers, [#{grpc_opts => #{service_protos => [route_guide_pb],
                                                            services => #{'routeguide.RouteGuide' =>
                                                                              routeguide_route_guide}},
                                             transport_opts => #{}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(unary_interceptor, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}], #{}}]}),
    application:set_env(grpcbox, servers,
                        [#{grpc_opts => #{service_protos => [route_guide_pb],
                                          services => #{'routeguide.RouteGuide' =>
                                                            routeguide_route_guide},
                                          unary_interceptor => fun(Ctx, _Req, _, Method) ->
                                                                       Method(Ctx, #{latitude => 30,
                                                                                     longitude => 90})
                                                               end},
                           transport_opts => #{}}]),
    application:ensure_all_started(grpcbox),

    Config;
init_per_testcase(chain_interceptor, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}], #{}}]}),
    application:set_env(grpcbox, servers,
                        [#{grpc_opts => #{service_protos => [route_guide_pb],
                                          services => #{'routeguide.RouteGuide' => routeguide_route_guide},
                                          unary_interceptor =>
                                              grpcbox_chain_interceptor:unary([fun ?MODULE:one/4,
                                                                               fun ?MODULE:two/4,
                                                                               fun ?MODULE:three/4])},
                           transport_opts => #{}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(trace_interceptor, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}], #{}}]}),
    application:ensure_all_started(opencensus),
    application:set_env(grpcbox, servers,
                        [#{grpc_opts => #{service_protos => [route_guide_pb],
                                          services => #{'routeguide.RouteGuide' => routeguide_route_guide},
                                          unary_interceptor =>
                                              grpcbox_chain_interceptor:unary([fun grpcbox_trace:unary/4,
                                                                               fun ?MODULE:trace_to_trailer/4])},
                           transport_opts => #{}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(stream_interceptor, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}], #{}}]}),
    application:set_env(grpcbox, servers,
                        [#{grpc_opts => #{service_protos => [route_guide_pb],
                                          services => #{'routeguide.RouteGuide' => routeguide_route_guide},
                                          stream_interceptor =>
                                              fun(Ref, Stream, _ServerInfo, Handler) ->
                                                      grpcbox_stream:add_trailers([{<<"x-grpc-stream-interceptor">>,
                                                                                    <<"true">>}],
                                                                                  Stream),
                                                      Handler(Ref, Stream)
                                              end},
                           transport_opts => #{}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(bidirectional, Config) ->
    application:load(grpcbox),
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}], #{}}]}),
    application:set_env(grpcbox, servers,
                        [#{grpc_opts => #{service_protos => [route_guide_pb],
                                          services => #{'routeguide.RouteGuide' => routeguide_route_guide}}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(stress_test, Config) ->
    application:load(grpcbox),
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}], #{}}]}),
    application:set_env(grpcbox, servers,
                        [#{grpc_opts => #{service_protos => [route_guide_pb],
                                          services => #{'routeguide.RouteGuide' => routeguide_route_guide}}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(client_stream, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}], #{}}]}),
    application:set_env(grpcbox, servers,
                        [#{grpc_opts => #{service_protos => [route_guide_pb],
                                          services => #{'routeguide.RouteGuide' => routeguide_route_guide}}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(compression, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}], #{}}]}),
    application:set_env(grpcbox, servers,
                        [#{grpc_opts => #{service_protos => [route_guide_pb],
                                          services => #{'routeguide.RouteGuide' => routeguide_route_guide}}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(stats_handler, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}], #{}}]}),
    application:set_env(grpcbox, servers,
                        [#{grpc_opts => #{service_protos => [route_guide_pb],
                                          services => #{'routeguide.RouteGuide' => routeguide_route_guide},
                                          stats_handler => test_stats_handler}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(health_service, Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}],
                                                         #{}}]}),
    application:set_env(grpcbox, servers,
                        [#{grpc_opts => #{service_protos => [grpcbox_health_pb],
                                          services => #{'grpc.health.v1.Health' => grpcbox_health_service}}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(reflection_service, Config) ->
    application:load(grpcbox),
    application:set_env(grpcbox, client, #{channels => [{default_channel,
                                                         [{http, "localhost", 8080, []}], #{}}]}),
    application:set_env(grpcbox, servers,
                        [#{grpc_opts => #{service_protos => [route_guide_pb,
                                                             grpcbox_reflection_pb,
                                                             grpcbox_health_pb],
                                          services => #{'grpc.reflection.v1alpha.ServerReflection'
                                                        => grpcbox_reflection_service,
                                                        'routeguide.RouteGuide' => routeguide_route_guide,
                                                        'grpc.health.v1.Health' => grpcbox_health_service}}}]),
    application:ensure_all_started(grpcbox),
    Config;
init_per_testcase(_, Config) ->
    Config.

end_per_testcase(unary_interceptor, _Config) ->
    ?assertMatch(ok, grpcbox_services_simple_sup:terminate_child(#{ip => {0, 0, 0, 0},
                                                                   port => 8080})),
    application:stop(grpcbox),
    ok;
end_per_testcase(unary_client_interceptor, _Config) ->
    ?assertMatch(ok, grpcbox_services_simple_sup:terminate_child(#{ip => {0, 0, 0, 0},
                                                                   port => 8080})),
    application:stop(grpcbox),
    ok;
end_per_testcase(chain_interceptor, _Config) ->
    ?assertMatch(ok, grpcbox_services_simple_sup:terminate_child(#{ip => {0, 0, 0, 0},
                                                                   port => 8080})),
    application:stop(grpcbox),
    ok;
end_per_testcase(trace_interceptor, _Config) ->
    application:stop(opencensus),
    ?assertMatch(ok, grpcbox_services_simple_sup:terminate_child(#{ip => {0, 0, 0, 0},
                                                                   port => 8080})),
    application:stop(grpcbox),
    ok;
end_per_testcase(health_service, _Config) ->
    ?assertMatch(ok, grpcbox_services_simple_sup:terminate_child(#{ip => {0, 0, 0, 0},
                                                                   port => 8080})),
    application:stop(grpcbox),
    ok;
end_per_testcase(unary_authenticated, _Config) ->
    ok;
end_per_testcase(unary_no_auth, _Config) ->
    ok;
end_per_testcase(multiple_servers, _Config) ->
    ok;
end_per_testcase(unimplemented, _Config) ->
    ok;
end_per_testcase(unauthorized, _Config) ->
    ok;
end_per_testcase(generate_error, _Config) ->
    ok;
end_per_testcase(streaming_generate_error, _Config) ->
    ok;
end_per_testcase(closed_stream, _Config) ->
    ok;
end_per_testcase(_, _Config) ->
    application:stop(grpcbox),
    ok.

initially_down_service(_Config) ->
    Point = #{latitude => 409146138, longitude => -746188906},
    Ctx = ctx:with_deadline_after(ctx:new(), 5, second),
    ?assertMatch({error, econnrefused}, routeguide_route_guide_client:get_feature(Ctx, Point)),

    grpcbox:start_server(#{grpc_opts => #{service_protos => [route_guide_pb],
                                          services => #{'routeguide.RouteGuide' =>
                                                            routeguide_route_guide}}}),

    {ok, _Feature, _} = routeguide_route_guide_client:get_feature(Ctx, Point).

unimplemented(_Config) ->
    Def = #grpcbox_def{service = 'routeguide.RouteGuide',
                       marshal_fun = fun(I) -> route_guide_pb:encode_msg(I, point) end,
                       unmarshal_fun = fun(I) -> route_guide_pb:encode_msg(I, feature) end},
    ?assertMatch({error, {?GRPC_STATUS_UNIMPLEMENTED, _}, #{headers := #{}, trailers := #{}}},
                 grpcbox_client:unary(ctx:new(), <<"/routeguide.RouteGuide/NotReal">>, #{}, Def, #{})),

    {ok, S} = grpcbox_client:stream(ctx:new(), <<"/routeguide.RouteGuide/NotReal">>, #{}, Def, #{}),
    ?assertMatch({error, {?GRPC_STATUS_UNIMPLEMENTED, _}, #{trailers := #{}}},
                 grpcbox_client:recv_data(S)).

unauthorized(_Config) ->
    Point = #{latitude => 409146138, longitude => -746188906},
    Ctx = ctx:new(),
    {error, {?GRPC_STATUS_UNAUTHENTICATED, _}, #{headers := #{}, trailers := #{}}}
        = routeguide_route_guide_client:get_feature(Ctx, Point).

generate_error(_Config) ->
    Response = routeguide_route_guide_client:generate_error(#{}),
    ?assertMatch({error, {?GRPC_STATUS_INTERNAL, <<"error_message">>}, _}, Response),
    {error, _, #{trailers := Trailers}} = Response,
    ?assertEqual(<<"error_trailer">>, maps:get(<<"generate_error_trailer">>, Trailers, undefined)).

streaming_generate_error(_Config) ->
    {ok, Stream} = routeguide_route_guide_client:streaming_generate_error(#{}),
    ?assertMatch({ok, #{<<":status">> := <<"200">>}}, grpcbox_client:recv_headers(Stream)),
    Response = grpcbox_client:recv_data(Stream),
    ?assertMatch({error, {?GRPC_STATUS_INTERNAL, <<"error_message">>}, _}, Response),
    {error, _, #{trailers := Trailers}} = Response,
    ?assertEqual(<<"error_trailer">>, maps:get(<<"generate_error_trailer">>, Trailers, undefined)).

closed_stream(_Config) ->
    {ok, S} = routeguide_route_guide_client:record_route(ctx:new()),
    ok = grpcbox_client:send(S, #{latitude => 409146138, longitude => -746188906}),
    ok = grpcbox_client:send(S, #{latitude => 234818903, longitude => -823423910}),
    ?assertMatch(ok, grpcbox_client:close_send(S)),

    %% TODO: should this error? does send need to be a call?
    %% ?assertMatch(ok, grpcbox_client:send(S, #{latitude => 234818903, longitude => -823423910})),

    ?assertMatch({ok, #{point_count := 2}}, grpcbox_client:recv_data(S)),
    ?assertMatch({ok, _}, grpcbox_client:recv_trailers(S)),
    ?assertMatch(stream_finished, grpcbox_client:recv_data(S)),

    %% verify you get stream finished also when not having received the trailers
    {ok, S1} = routeguide_route_guide_client:record_route(ctx:new()),
    ok = grpcbox_client:send(S1, #{latitude => 409146138, longitude => -746188906}),
    ok = grpcbox_client:send(S1, #{latitude => 234818903, longitude => -823423910}),
    ?assertMatch(ok, grpcbox_client:close_send(S1)),
    ?assertMatch({ok, #{point_count := 2}}, grpcbox_client:recv_data(S1)),
    ?assertMatch(stream_finished, grpcbox_client:recv_data(S1)).

compression(_Config) ->
    Point = #{latitude => 409146138, longitude => -746188906},
    Ctx = ctx:new(),
    ?assertMatch({error, {unknown_encoding, something}},
                 routeguide_route_guide_client:get_feature(Ctx, Point, #{encoding => something})),

    {ok, Feature, _} = routeguide_route_guide_client:get_feature(Point, #{encoding => gzip}),
    ?assertEqual(#{location =>
                       #{latitude => 409146138, longitude => -746188906},
                   name =>
                       <<"Berkshire Valley Management Area Trail, Jefferson, NJ, USA">>}, Feature).

health_service(_Config) ->
    Ctx = ctx:new(),
    ?assertMatch({ok, #{status := 'SERVING'}, _}, grpcbox_health_client:check(Ctx, #{})),
    ?assertMatch({ok, #{status := 'UNKNOWN'}, _},
                 grpcbox_health_client:check(Ctx, #{service => <<"grpc.health.v1.Health">>})),
    ?assertMatch({ok, #{status := 'UNKNOWN'}, _},
                 grpcbox_health_client:check(Ctx, #{service => <<"something else">>})).

reflection_service(_Config) ->
    {ok, S} = grpcbox_reflection_client:server_reflection_info(),

    ok = grpcbox_client:send(S, #{message_request => {list_services, <<>>}}),
    ?assertMatch({ok, #{message_response :=
                            {list_services_response,
                             #{service := [#{name := <<"grpc.health.v1.Health">>},
                                           #{name := <<"grpc.reflection.v1alpha.ServerReflection">>},
                                           #{name := <<"routeguide.RouteGuide">>}]}}}},
                 grpcbox_client:recv_data(S)),

    ok = grpcbox_client:send(S, #{message_request => {all_extension_numbers_of_type, <<>>}}),
    ?assertMatch({ok, #{message_response :=
                            {error_response,#{error_code := 12,
                                              error_message :=
                                                  <<"unimplemented method since extensions removed in proto3">>}}}},
                 grpcbox_client:recv_data(S)),

    ok = grpcbox_client:send(S, #{message_request => {file_containing_extension, #{}}}),
    ?assertMatch({ok, #{message_response :=
                            {error_response,#{error_code := 12,
                                              error_message :=
                                                  <<"unimplemented method since extensions removed in proto3">>}}}},
                 grpcbox_client:recv_data(S)),

    ok = grpcbox_client:send(S, #{message_request => {file_by_filename, <<"health">>}}),
    ?assertMatch({ok, #{message_response :=
                            {file_descriptor_response,
                             #{file_descriptor_proto := [_]}}}},
                 grpcbox_client:recv_data(S)),

    ok = grpcbox_client:send(S, #{message_request => {file_containing_symbol, <<"routeguide.RouteGuide">>}}),
    ?assertMatch({ok, #{message_response :=
                            {file_descriptor_response,
                             #{file_descriptor_proto := [_]}}}},
                 grpcbox_client:recv_data(S)),

    ok = grpcbox_client:send(S, #{message_request => {file_containing_symbol, <<"grpc.health.v1.HealthCheckResponse.ServingStatus">>}}),
    ?assertMatch({ok, #{message_response :=
                            {file_descriptor_response,
                             #{file_descriptor_proto := [_]}}}},
                 grpcbox_client:recv_data(S)),

    %% closes the stream, waits for an 'end of stream' message and then returns the received data
    ?assertMatch(ok, grpcbox_client:close_send(S)).

stats_handler(_Config) ->
    register(stats_pid, self()),

    Point = #{latitude => 409146138, longitude => -746188906},
    Ctx = ctx:new(),
    {ok, Feature, _} = routeguide_route_guide_client:get_feature(Ctx, Point, #{encoding => gzip}),
    ?assertEqual(#{location =>
                       #{latitude => 409146138, longitude => -746188906},
                   name =>
                       <<"Berkshire Valley Management Area Trail, Jefferson, NJ, USA">>}, Feature),

    F = fun L(Stats) ->
                receive
                    {rpc_begin, T} ->
                        L(Stats#{rpc_begin => T});
                    {out_payload, USize, CSize} ->
                        L(Stats#{out_payload => {USize, CSize}});
                    {in_payload, USize, CSize} ->
                        L(Stats#{in_payload => {USize, CSize}});
                    {rpc_end, T} ->
                        Stats#{rpc_end => T}
                after
                    2000 ->
                        exit(1)
                end
        end,
    Stats = F(#{}),

    {OutUSize, OutCSize} = maps:get(out_payload, Stats),
    ?assert(is_integer(OutUSize) andalso is_integer(OutCSize)),

    {InUSize, InCSize} = maps:get(in_payload, Stats),
    ?assert(is_integer(InUSize) andalso is_integer(InCSize)),

    ?assert(maps:get(rpc_end, Stats) > maps:get(rpc_begin, Stats)).

unary_no_auth(_Config) ->
    unary(_Config).

unary_authenticated(Config) ->
    unary(Config).

multiple_servers(_Config) ->
    application:set_env(grpcbox, client, #{channels => [{default_channel, [{http, "localhost", 8080, []},
                                                                           {http, "localhost", 8081, []}]},
                                                        #{balancer => round_robin}]}),
    ?assertMatch({ok, _}, grpcbox:start_server(#{grpc_opts => #{service_protos => [route_guide_pb],
                                                                services => #{'routeguide.RouteGuide' => routeguide_route_guide}},
                                                 listen_opts => #{port => 8081}})),
    unary(_Config),
    unary(_Config).

bidirectional(Config) ->
    {ok, S} = routeguide_route_guide_client:route_chat(ctx:new(), proplists:get_value(options, Config, #{})),
    %% send 2 before receiving since the server only sends what it already had in its list of messages for the
    %% location of your last send.
    ok = grpcbox_client:send(S, #{location => #{latitude => 1, longitude => 1}, message => <<"hello there">>}),
    ok = grpcbox_client:send(S, #{location => #{latitude => 1, longitude => 1}, message => <<"hello there">>}),
    ?assertMatch({ok, #{message := <<"hello there">>}}, grpcbox_client:recv_data(S)),
    ok = grpcbox_client:send(S, #{location => #{latitude => 1, longitude => 1}, message => <<"hello there">>}),

    %% closes the stream, waits for an 'end of stream' message and then returns the received data
    ?assertMatch(ok, grpcbox_client:close_send(S)).
%% TODO: add tests to ensure stream pids are gone and that accidental recvs and such after a close don't hang

client_stream(_Config) ->
    {ok, S} = routeguide_route_guide_client:record_route(ctx:new()),
    ok = grpcbox_client:send(S, #{latitude => 409146138, longitude => -746188906}),
    ok = grpcbox_client:send(S, #{latitude => 234818903, longitude => -823423910}),
    ?assertMatch(ok, grpcbox_client:close_send(S)),
    ?assertMatch({ok, #{point_count := 2}}, grpcbox_client:recv_data(S)).
%% TODO: add tests to ensure stream pids are gone and that accidental recvs and such after a close don't hang

unary(_Channel) ->
    Point = #{latitude => 409146138, longitude => -746188906},
    {ok, Feature, _} = routeguide_route_guide_client:get_feature(Point),
    ?assertEqual(#{location =>
                       #{latitude => 409146138, longitude => -746188906},
                   name =>
                       <<"Berkshire Valley Management Area Trail, Jefferson, NJ, USA">>}, Feature).

unary_client_interceptor(_Config) ->
    %% client side interceptor replaces the point with lat 30 and long 90
    Point = #{latitude => 409146138, longitude => -746188906},
    {ok, Feature, _} = routeguide_route_guide_client:get_feature(Point),
    ?assertEqual(#{location =>
                       #{latitude => 30, longitude => 90},
                   name => <<"">>}, Feature).

unary_interceptor(_Config) ->
    %% our test interceptor replaces the point with lat 30 and long 90
    Point = #{latitude => 409146138, longitude => -746188906},
    {ok, Feature, _} = routeguide_route_guide_client:get_feature(Point),
    ?assertEqual(#{location =>
                       #{latitude => 30, longitude => 90},
                   name => <<"">>}, Feature).

chain_interceptor(_Config) ->
    Point = #{latitude => 409146138, longitude => -746188906},
    {ok, _Feature, #{trailers := Trailers}} = routeguide_route_guide_client:get_feature(ctx:background(), Point),
    ?assertMatch(#{<<"x-grpc-interceptor-one">> := <<"one">>,
                   <<"x-grpc-interceptor-three">> := <<"three">>,
                   <<"x-grpc-interceptor-two">> := <<"two">>}, Trailers).

%% include a trace context and test that it works by having a second interceptor add
%% the trace id from the context as a response trailer.
trace_interceptor(_Config) ->
    Point = #{latitude => 409146138, longitude => -746188906},
    Ctx = oc_trace:with_child_span(ctx:background(), <<"grpc-client-call">>),
    Context = oc_propagation_binary:encode(oc_trace:from_ctx(Ctx)),
    Metadata = #{<<"grpc-trace-bin">> => Context},
    Ctx1 = grpcbox_metadata:append_to_outgoing_ctx(Ctx, Metadata),
    {_, _Feature, #{trailers := Trailers}} = routeguide_route_guide_client:get_feature(Ctx1, Point),
    BinTraceId = integer_to_binary((oc_trace:from_ctx(Ctx))#span_ctx.trace_id),
    ?assertMatch(BinTraceId, maps:get(<<"x-grpc-trace-id">>, Trailers)).

stream_interceptor(_Config) ->
    {ok, Stream} =
        routeguide_route_guide_client:list_features(ctx:background(), #{hi => #{latitude => 1, longitude => 2},
                                                                        lo => #{latitude => 3, longitude => 5}}),
    ?assertMatch({ok, #{<<":status">> := <<"200">>}}, grpcbox_client:recv_headers(Stream)),
    ?assertMatch({ok, #{name := <<"Tour Eiffel">>}}, grpcbox_client:recv_data(Stream)),
    ?assertMatch({ok, #{name := <<"Louvre">>}}, grpcbox_client:recv_data(Stream)),
    ?assertMatch({ok, {_, _, #{<<"x-grpc-stream-interceptor">> := <<"true">>}}}, grpcbox_client:recv_trailers(Stream)).

stress_test_function(Fun, Config, Ref, Parent) ->
    Parent ! {stress_test, Ref, Fun(Config)}.

stress_test(Config) ->
    stress_test(Config,
        erlang:list_to_integer(
            os:getenv("GRPCBOX_STRESS_TEST", "10")
        )).

stress_test(Config, Count) ->
    lists:foreach(fun
        (ProcId) ->
            Parent = self(),
            spawn(fun() ->
                Channel = erlang:list_to_atom("proc_" ++ erlang:integer_to_list(ProcId)),
                erlang:register(Channel, self()),
                {ok, _Pid} = grpcbox_channel:add_channel(
                    Channel,
                    [{http, "localhost", 8080, []}],
                    #{}
                ),
                lists:foldl(fun
                    (_, not_ready) ->
                        timer:sleep(10),
                        grpcbox_channel:is_ready(Channel);
                    (_,Acc) ->
                        Acc
                end, not_ready, lists:seq(1, 100)),

                stress_test_function(fun bidirectional/1,
                    [{options,#{channel => Channel}} | Config],
                    ProcId, Parent),
                ok
                %% grpcbox_channel:delete_channel(Pid)
            end)
    end, lists:seq(1, Count)),

    Loop = fun Loop(LoopCount) ->
        receive
            {stress_test, _Ref, _Reply} when LoopCount < Count ->
                Loop(LoopCount + 1);
            {stress_test, _Ref, _Reply} when LoopCount < Count ->
                LoopCount + 1
        after
            2000 ->
                LoopCount
        end
    end,
    ?assertEqual(Count, Loop(0)).

%%

cert_dir(Config) ->
    DataDir = ?config(data_dir, Config),
    filename:join(DataDir, "certificates").

cert(Config, FileName) ->
    R = filename:join([cert_dir(Config), FileName]),
    true = filelib:is_file(R),
    R.

one(Ctx, Message, _ServerInfo, Handler) ->
    Trailer = grpcbox_metadata:pairs([{<<"x-grpc-interceptor-one">>, <<"one">>}]),
    Ctx1 = grpcbox_stream:add_trailers(Ctx, Trailer),
    Handler(Ctx1, Message).

two(Ctx, Message, _ServerInfo, Handler) ->
    Trailer = grpcbox_metadata:pairs([{<<"x-grpc-interceptor-two">>, <<"two">>}]),
    Ctx1 = grpcbox_stream:add_trailers(Ctx, Trailer),
    Handler(Ctx1, Message).

three(Ctx, Message, _ServerInfo, Handler) ->
    Trailer = grpcbox_metadata:pairs([{<<"x-grpc-interceptor-three">>, <<"three">>}]),
    Ctx1 = grpcbox_stream:add_trailers(Ctx, Trailer),
    Handler(Ctx1, Message).

trace_to_trailer(Ctx, Message, _ServerInfo, Handler) ->
    SpanCtx = oc_trace:from_ctx(Ctx),
    BinTraceId = integer_to_binary(SpanCtx#span_ctx.trace_id),
    Trailer = grpcbox_metadata:pairs([{<<"x-grpc-trace-id">>, BinTraceId}]),
    Ctx1 = grpcbox_stream:add_trailers(Ctx, Trailer),
    Handler(Ctx1, Message).
