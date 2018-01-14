-module(grpcbox_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-include_lib("opencensus/include/opencensus.hrl").

groups() ->
    [{ssl, [], [unary_authenticated]},
     {tcp, [], [unary_no_auth, multiple_servers]}].

all() ->
    [{group, ssl}, {group, tcp}, unary_interceptor, chain_interceptor, trace_interceptor].

init_per_suite(Config) ->
    DataDir = ?config(data_dir, Config),
    application:load(grpcbox),

    Proto = filename:join(DataDir, "route_guide.proto"),
    {ok, Mod, Code} = gpb_compile:file(Proto, [binary,
                                               {rename,{msg_name,snake_case}},
                                               {rename,{msg_fqname,base_name}},
                                               use_packages, maps, type_specs,
                                               strings_as_binaries,
                                               {i, DataDir},
                                               {module_name_suffix, "_pb"}]),
    code:load_binary(Mod, Proto, Code),
    grpc_client:compile(Proto, [{strings_as_binaries, true}]),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(ssl, Config) ->
    ClientCerts = filename:join(cert_dir(Config), "clients"),
    application:set_env(grpcbox, grpc_opts, #{service_protos => [route_guide_pb],
                                              client_cert_dir => ClientCerts}),
    application:set_env(grpcbox, transport_opts, #{ssl => true,
                                                   keyfile => cert(Config, "localhost.key"),
                                                   certfile => cert(Config, "localhost.crt"),
                                                   cacertfile => cert(Config, "My_Root_CA.crt")}),

    application:ensure_all_started(grpcbox),
    ?assertMatch({ok, _}, grpcbox_sup:start_child()),
    Config;
init_per_group(tcp, Config) ->
    application:set_env(grpcbox, grpc_opts, #{service_protos => [route_guide_pb]}),
    application:set_env(grpcbox, transport_opts, #{}),
    application:ensure_all_started(grpcbox),
    ?assertMatch({ok, _}, grpcbox_sup:start_child()),
    Config.

end_per_group(_, _Config) ->
    ?assertMatch(ok, grpcbox_sup:terminate_child(#{ip => {0,0,0,0},
                                                   port => 8080})),
    application:stop(grpcbox),
    ok.

init_per_testcase(unary_interceptor, Config) ->
    application:set_env(grpcbox, grpc_opts, #{service_protos => [route_guide_pb],
                                              unary_interceptor => fun(Ctx, _Req, _, Method) ->
                                                                           Method(Ctx, #{latitude => 30,
                                                                                         longitude => 90})
                                                                   end}),
    application:set_env(grpcbox, transport_opts, #{}),
    application:ensure_all_started(grpcbox),
    ?assertMatch({ok, _}, grpcbox_sup:start_child()),
    Config;
init_per_testcase(chain_interceptor, Config) ->
    application:set_env(grpcbox, grpc_opts, #{service_protos => [route_guide_pb],
                                              unary_interceptor =>
                                                  grpcbox_chain_interceptor:unary([fun ?MODULE:one/4,
                                                                                   fun ?MODULE:two/4,
                                                                                   fun ?MODULE:three/4])}),
    application:set_env(grpcbox, transport_opts, #{}),
    application:ensure_all_started(grpcbox),
    ?assertMatch({ok, _}, grpcbox_sup:start_child()),
    Config;
init_per_testcase(trace_interceptor, Config) ->
    application:ensure_all_started(opencensus),
    application:set_env(grpcbox, grpc_opts, #{service_protos => [route_guide_pb],
                                              unary_interceptor =>
                                                  grpcbox_chain_interceptor:unary([fun grpcbox_trace:unary/4,
                                                                                   fun ?MODULE:trace_to_trailer/4])}),
    application:set_env(grpcbox, transport_opts, #{}),
    application:ensure_all_started(grpcbox),
    ?assertMatch({ok, _}, grpcbox_sup:start_child()),
    Config;
init_per_testcase(_, Config) ->
    Config.

end_per_testcase(unary_interceptor, _Config) ->
    ?assertMatch(ok, grpcbox_sup:terminate_child(#{ip => {0,0,0,0},
                                                   port => 8080})),
    application:stop(grpcbox),
    ok;
end_per_testcase(chain_interceptor, _Config) ->
    ?assertMatch(ok, grpcbox_sup:terminate_child(#{ip => {0,0,0,0},
                                                   port => 8080})),
    application:stop(grpcbox),
    ok;
end_per_testcase(trace_interceptor, _Config) ->
    application:stop(opencensus),
    ?assertMatch(ok, grpcbox_sup:terminate_child(#{ip => {0,0,0,0},
                                                   port => 8080})),
    application:stop(grpcbox),
    ok;
end_per_testcase(_, _Config) ->
    ok.

unary_no_auth(_Config) ->
    {ok, Connection} = grpc_client:connect(tcp, "localhost", 8080),
    unary(Connection).

unary_authenticated(Config) ->
    Options = [{transport_options, [{certfile, cert(Config, "127.0.0.1.crt")},
                                    {keyfile, cert(Config, "127.0.0.1.key")},
                                    {cacertfile, cert(Config, "My_Root_CA.crt")}]}],
    {ok, Connection} = grpc_client:connect(ssl, "localhost", 8080, Options),
    unary(Connection).

multiple_servers(_Config) ->
    ?assertMatch({ok, _}, grpcbox_sup:start_child(#{grpc_opts => #{service_protos => [route_guide_pb]},
                                                    listen_opts => #{port => 8081}})),
    {ok, Connection} = grpc_client:connect(tcp, "localhost", 8080),
    unary(Connection),

    {ok, Connection2} = grpc_client:connect(tcp, "localhost", 8081),
    unary(Connection2).

unary(Connection) ->
    Point = #{latitude => 409146138, longitude => -746188906},
    {ok, #{result := Feature}} = grpc_client:unary(Connection, Point, 'RouteGuide', 'GetFeature', route_guide, []),
    ?assertEqual(#{location =>
                       #{latitude => 409146138,longitude => -746188906},
                   name =>
                       <<"Berkshire Valley Management Area Trail, Jefferson, NJ, USA">>}, Feature).

unary_interceptor(_Config) ->
    {ok, Connection} = grpc_client:connect(tcp, "localhost", 8080),

    %% our test interceptor replaces the point with lat 30 and long 90
    Point = #{latitude => 409146138, longitude => -746188906},
    {ok, #{result := Feature}} = grpc_client:unary(Connection, Point, 'RouteGuide', 'GetFeature', route_guide, []),
    ?assertEqual(#{location =>
                       #{latitude => 30, longitude => 90},
                   name => <<"">>}, Feature).

chain_interceptor(_Config) ->
    {ok, Connection} = grpc_client:connect(tcp, "localhost", 8080),

    %% our test interceptor replaces the point with lat 30 and long 90
    Point = #{latitude => 409146138, longitude => -746188906},
    {ok, #{trailers := Trailers}} = grpc_client:unary(Connection, Point, 'RouteGuide', 'GetFeature', route_guide, []),
    ?assertMatch(#{<<"x-grpc-interceptor-one">> := <<"one">>,
                   <<"x-grpc-interceptor-three">> := <<"three">>,
                   <<"x-grpc-interceptor-two">> := <<"two">>}, Trailers).

trace_interceptor(_Config) ->
    {ok, Connection} = grpc_client:connect(tcp, "localhost", 8080),

    %% our test interceptor replaces the point with lat 30 and long 90
    Point = #{latitude => 409146138, longitude => -746188906},
    Span = opencensus:start_span(<<"grpc-client-call">>, opencensus:start_trace()),
    {ok, Context} = oc_trace_context_binary:encode(opencensus:context(Span)),
    Metadata = #{<<"grpc-trace-bin">> => Context},
    {ok, #{trailers := Trailers}} = grpc_client:unary(Connection, Point, 'RouteGuide', 'GetFeature',
                                                      route_guide, [{metadata, Metadata}]),
    BinTraceId = integer_to_binary(Span#span.trace_id),
    ?assertMatch(#{<<"x-grpc-trace-id">> := BinTraceId}, Trailers).

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
    Span = ctx:get(Ctx, active_span),
    BinTraceId = integer_to_binary(Span#span.trace_id),
    Trailer = grpcbox_metadata:pairs([{<<"x-grpc-trace-id">>, BinTraceId}]),
    Ctx1 = grpcbox_stream:add_trailers(Ctx, Trailer),
    Handler(Ctx1, Message).
