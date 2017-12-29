%%%-------------------------------------------------------------------
%% @doc grpcbox top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_sup).

-behaviour(supervisor).

-export([start_link/4]).

-export([init/1]).

-define(SERVER, ?MODULE).

start_link(ChatterboxOpts, ListenOpts, PoolOpts, TransportOpts) ->
    supervisor:start_link(?MODULE, [ChatterboxOpts, ListenOpts, PoolOpts, TransportOpts]).

init([ChatterboxOpts, ListenOpts, PoolOpts, TransportOpts]) ->
    RestartStrategy = #{strategy => rest_for_one},
    Pool = #{id => grpcbox_pool,
             start => {grpcbox_pool, start_link, [chatterbox:settings(server, ChatterboxOpts), TransportOpts]}},
    Socket = #{id => grpcbox_socket,
               start => {grpcbox_socket, start_link, [ListenOpts, PoolOpts]}},
    {ok, {RestartStrategy, [Pool, Socket]}}.
