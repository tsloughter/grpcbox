-module(grpcbox_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

groups() ->
    [{ssl, [], [unary_authenticated]},
     {tcp, [], [unary_no_auth]}].

all() ->
    [{group, ssl}, {group, tcp}].

init_per_suite(Config) ->
    DataDir = ?config(data_dir, Config),
    application:load(grpcbox),
    application:set_env(grpcbox, service_protos, [route_guide_pb]),

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
    application:set_env(grpcbox, options, [{client_cert_dir, ClientCerts}]),
    application:set_env(chatterbox, ssl, true),
    application:set_env(chatterbox, ssl_options, [{certfile, cert(Config, "localhost.crt")},
                                                  {keyfile, cert(Config, "localhost.key")},
                                                  {honor_cipher_order, false},
                                                  {cacertfile, cert(Config, "My_Root_CA.crt")},
                                                  {fail_if_no_peer_cert, true},
                                                  {verify, verify_peer},
                                                  {versions, ['tlsv1.2']},
                                                  {next_protocols_advertised, [<<"h2">>]}]),

    application:ensure_all_started(grpcbox),
    Config;
init_per_group(tcp, Config) ->
    application:set_env(chatterbox, ssl, false),
    application:ensure_all_started(grpcbox),
    Config.

end_per_group(_, _Config) ->
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
