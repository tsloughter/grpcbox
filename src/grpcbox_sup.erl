%%%-------------------------------------------------------------------
%% @doc grpcbox top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_sup).

-behaviour(supervisor).

-export([start_link/0,
         start_child/0,
         start_child/1,
         terminate_child/1]).
-export([init/1]).

-include("grpcbox.hrl").

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_child() ->
    GrpcOpts = application:get_env(grpcbox, grpc_opts, #{}),
    ServerOpts = application:get_env(grpcbox, server_opts, #{}),
    ListenOpts = application:get_env(grpcbox, listen_opts, #{}),
    PoolOpts = application:get_env(grpcbox, pool_opts, #{}),
    TransportOpts = application:get_env(grpcbox, transport_opts, #{}),
    start_child(#{server_opts => ServerOpts,
                  grpc_opts => GrpcOpts,
                  listen_opts => ListenOpts,
                  pool_opts => PoolOpts,
                  transport_opts => TransportOpts}).

start_child(Opts) ->
    GrpcOpts = maps:get(grpc_opts, Opts, #{}),
    ServerOpts = maps:get(server_opts, Opts, #{}),
    ListenOpts = maps:get(listen_opts, Opts, #{}),
    PoolOpts = maps:get(pool_opts, Opts, #{}),
    TransportOpts = maps:get(transport_opts, Opts, #{}),
    supervisor:start_child(?SERVER, [ServerOpts, GrpcOpts, ListenOpts, PoolOpts, TransportOpts]).

terminate_child(ListenOpts) ->
    supervisor:terminate_child(?SERVER, whereis(grpcbox_services_sup:services_sup_name(ListenOpts))).

init(_Args) ->
    SupFlags = #{strategy => simple_one_for_one,
                 intensity => 0,
                 period => 1},
    ChildSpecs = [#{id => grpcbox_services_sup,
                    start => {grpcbox_services_sup, start_link, []},
                    type => supervisor,
                    shutdown => brutal_kill}],
    {ok, {SupFlags, ChildSpecs}}.
