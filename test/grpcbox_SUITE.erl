-module(grpcbox_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

groups() ->
    [{ssl, [], [unary_authenticated]},
     {tcp, [], [unary_no_auth, multiple_servers]}].

all() ->
    [{group, ssl}, {group, tcp}].

init_per_suite(Config) ->
    DataDir = ?config(data_dir, Config),
    application:load(grpcbox),

    Proto = filename:join(DataDir, "route_guide.proto"),
    {ok, Mod, Code} = gpb_compile:file(Proto, [binary,
                                               {i, DataDir},
                                               {strings_as_binaries, true},
                                               {module_name_suffix, "_pb"},
                                               use_packages,
                                               maps]),
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

cert_dir(Config) ->
    DataDir = ?config(data_dir, Config),
    filename:join(DataDir, "certificates").

cert(Config, FileName) ->
    R = filename:join([cert_dir(Config), FileName]),
    true = filelib:is_file(R),
    R.
