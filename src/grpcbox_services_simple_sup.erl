%%%-------------------------------------------------------------------
%% @doc grpcbox services simple one for one supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_services_simple_sup).

-behaviour(supervisor).

-export([start_link/0,
         start_child/1,
         terminate_child/1]).
-export([init/1]).

-include("grpcbox.hrl").

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_child(Opts) ->
    GrpcOpts = maps:get(grpc_opts, Opts, #{}),
    ServerOpts = maps:get(server_opts, Opts, #{}),
    ListenOpts = maps:get(listen_opts, Opts, #{}),
    PoolOpts = maps:get(pool_opts, Opts, #{}),
    TransportOpts = maps:get(transport_opts, Opts, #{}),
    supervisor:start_child(?SERVER, [ServerOpts, GrpcOpts, ListenOpts, PoolOpts, TransportOpts]).

terminate_child(ListenOpts) ->
    case whereis(grpcbox_services_sup:services_sup_name(ListenOpts)) of
        undefined ->
            ok;
        Pid ->
            supervisor:terminate_child(?SERVER, Pid)
    end.

init(_Args) ->
    SupFlags = #{strategy => simple_one_for_one,
                 intensity => 5,
                 period => 10},
    ChildSpecs = [#{id => grpcbox_services_sup,
                    start => {grpcbox_services_sup, start_link, []},
                    type => supervisor,
                    restart => transient,
                    shutdown => 1000}],
    {ok, {SupFlags, ChildSpecs}}.
