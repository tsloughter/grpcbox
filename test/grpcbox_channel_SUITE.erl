-module(grpcbox_channel_SUITE).

-export([all/0,
        init_per_suite/1,
        end_per_suite/1,
        add_and_remove_endpoints/1]).

-include_lib("eunit/include/eunit.hrl").

all() ->
    [
        add_and_remove_endpoints
    ].
init_per_suite(_Config) ->
    application:set_env(grpcbox, servers, []),
    application:ensure_all_started(grpcbox),
    grpcbox_channel_sup:start_link(),
    grpcbox_channel_sup:start_child(default_channel, [{http, "127.0.0.1", 18080, []}], #{}),
    grpcbox_channel_sup:start_child(random_channel,
                                    [{http, "127.0.0.1", 18080, []}, {http, "127.0.0.1", 18081, []}, {http, "127.0.0.1", 18082, []}, {http, "127.0.0.1", 18083, []}],
                                    #{balancer => random}),
    grpcbox_channel_sup:start_child(hash_channel,
                                    [{http, "127.0.0.1", 18080, []}, {http, "127.0.0.1", 18081, []}, {http, "127.0.0.1", 18082, []}, {http, "127.0.0.1", 18083, []}],
                                    #{balancer => hash}),
    grpcbox_channel_sup:start_child(direct_channel,
                                    [{http, "127.0.0.1", 18080, []}, {http, "127.0.0.1", 18081, []}, {http, "127.0.0.1", 18082, []}, {http, "127.0.0.4", 18084, []}],
                                    #{ balancer => direct}),

    _Config.

end_per_suite(_Config) ->
    application:stop(grpcbox),
    ok.

add_and_remove_endpoints(_Config) ->
    grpcbox_channel:add_endpoints(default_channel, [{http, "127.0.0.1", 18081, []}, {http, "127.0.0.1", 18082, []}, {http, "127.0.0.1", 18083, []}]),
    ?assertEqual(4, length(gproc_pool:active_workers(default_channel))),
    grpcbox_channel:add_endpoints(default_channel, [{https, "127.0.0.1", 18081, []}, {https, "127.0.0.1", 18082, []}, {https, "127.0.0.1", 18083, []}]),
    ?assertEqual(7, length(gproc_pool:active_workers(default_channel))).
