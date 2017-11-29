-module(grpcbox_SUITE).

-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

all() ->
    [unary].

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
    application:ensure_all_started(grpcbox),
    Config.

end_per_suite(_Config) ->
    ok.

unary(_Config) ->
    {ok, Connection} = grpc_client:connect(tcp, "localhost", 8080),
    Point = #{latitude => 409146138, longitude => -746188906},
    {ok, #{result := Feature}} = grpc_client:unary(Connection, Point, 'RouteGuide', 'GetFeature', route_guide, []),
    ?assertEqual(#{location =>
                       #{latitude => 409146138,longitude => -746188906},
                   name =>
                       <<"Berkshire Valley Management Area Trail, Jefferson, NJ, USA">>}, Feature),
    ct:pal("Stream ~p", [Feature]).
