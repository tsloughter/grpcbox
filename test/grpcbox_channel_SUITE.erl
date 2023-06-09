-module(grpcbox_channel_SUITE).

-export([all/0,
         init_per_suite/1,
         end_per_suite/1,
         add_and_remove_endpoints/1,
         add_and_remove_endpoints_active_workers/1,
         pick_worker_strategy/1,
         pick_active_worker_strategy/1,
         pick_specify_worker_strategy/1
        ]).

-include_lib("eunit/include/eunit.hrl").

all() ->
    [
        add_and_remove_endpoints,
        add_and_remove_endpoints_active_workers,
        pick_worker_strategy,
        pick_active_worker_strategy,
        pick_specify_worker_strategy
    ].
init_per_suite(_Config) ->
    application:set_env(grpcbox, client, #{channel => []}),
    GrpcOptions = #{service_protos => [route_guide_pb], services => #{'routeguide.RouteGuide' => routeguide_route_guide}},
    Servers = [#{grpc_opts => GrpcOptions,
                 listen_opts => #{port => 18080, ip => {127,0,0,1}}},
                #{grpc_opts => GrpcOptions,
                 listen_opts => #{port => 18081, ip => {127,0,0,1}}},
                 #{grpc_opts => GrpcOptions,
                 listen_opts => #{port => 18082, ip => {127,0,0,1}}},
                 #{grpc_opts => GrpcOptions,
                 listen_opts => #{port => 18083, ip => {127,0,0,1}}}],
    application:set_env(grpcbox, servers, Servers),
    application:ensure_all_started(grpcbox),
    ct:sleep(1000),
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
    ?assertEqual(7, length(gproc_pool:active_workers(default_channel))),
    grpcbox_channel:remove_endpoints(default_channel, [{http, "127.0.0.1", 18081, []}, {http, "127.0.0.1", 18082, []}, {http, "127.0.0.1", 18083, []}], normal),
    ?assertEqual(4, length(gproc_pool:active_workers(default_channel))),
    grpcbox_channel:remove_endpoints(default_channel, [{https, "127.0.0.1", 18080, []}, {https, "127.0.0.1", 18081, []}, {https, "127.0.0.1", 18082, []}], normal),
    ?assertEqual(2, length(gproc_pool:active_workers(default_channel))).

add_and_remove_endpoints_active_workers(_Config) ->
    grpcbox_channel:add_endpoints(default_channel, [{http, "127.0.0.1", 18081, []}, {http, "127.0.0.1", 18082, []}, {http, "127.0.0.1", 18083, []}]),
    ct:sleep(1000),
    ?assertEqual(4, length(gproc_pool:active_workers({default_channel, active}))),
    grpcbox_channel:add_endpoints(default_channel, [{https, "127.0.0.1", 18081, []}, {https, "127.0.0.1", 18082, []}, {https, "127.0.0.1", 18083, []}]),
    ct:sleep(1000),
    ?assertEqual(4, length(gproc_pool:active_workers({default_channel, active}))),
    grpcbox_channel:remove_endpoints(default_channel, [{http, "127.0.0.1", 18081, []}, {http, "127.0.0.1", 18082, []}, {http, "127.0.0.1", 18083, []}], normal),
    ct:sleep(1000),
    ?assertEqual(1, length(gproc_pool:active_workers({default_channel, active}))),
    grpcbox_channel:remove_endpoints(default_channel, [{https, "127.0.0.1", 18081, []}, {https, "127.0.0.1", 18082, []}, {https, "127.0.0.1", 18083, []}], normal),
    ct:sleep(1000),
    ?assertEqual(1, length(gproc_pool:active_workers({default_channel, active}))).

pick_worker_strategy(_Config) ->
    ?assertEqual(ok, pick_worker(default_channel)),
    ?assertEqual(ok, pick_worker(random_channel)),
    ?assertEqual(ok, pick_worker(direct_channel, 1)),
    ?assertEqual(ok, pick_worker(hash_channel, 1)),
    ?assertEqual(error, pick_worker(default_channel, 1)),
    ?assertEqual(error, pick_worker(random_channel, 1)),
    ?assertEqual(error, pick_worker(direct_channel)),
    ?assertEqual(error, pick_worker(hash_channel)),
    ok.

pick_active_worker_strategy(_Config) ->
    ct:sleep(1000),
    ?assertEqual(ok, pick_worker({default_channel, active})),
    ?assertEqual(ok, pick_worker({random_channel, active})),
    ?assertEqual(ok, pick_worker({direct_channel, active}, 1)),
    ?assertEqual(ok, pick_worker({hash_channel, active}, 1)),
    ?assertEqual(error, pick_worker({default_channel, active}, 1)),
    ?assertEqual(error, pick_worker({random_channel, active}, 1)),
    ?assertEqual(error, pick_worker({direct_channel, active})),
    ?assertEqual(error, pick_worker({hash_channel, active})),
    ok.

pick_specify_worker_strategy(_Config) ->
    ?assertMatch({ok, _} ,grpcbox_channel:get(default_channel, stream, {http, "127.0.0.1", 18080, []})),
    ?assertEqual({error, not_found_endpoint} ,grpcbox_channel:get(default_channel, stream, {http, "127.0.0.1", 8080, []})),
    ?assertEqual({error, not_found_endpoint} ,grpcbox_channel:get(channel_xxx, stream, {http, "127.0.0.1", 8080, []})),
    ok.

pick_worker(Name, N) ->
    {R, _} = grpcbox_channel:pick(Name, unary, N),
    R.
pick_worker(Name) ->
    {R, _} = grpcbox_channel:pick(Name, unary, undefined),
    R.
