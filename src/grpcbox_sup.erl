%%%-------------------------------------------------------------------
%% @doc grpcbox top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_sup).

-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

-include("grpcbox.hrl").

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init(_Args) ->
    SupFlags = #{strategy => one_for_one,
                 intensity => 5,
                 period => 10},
    ChildSpecs = [#{id => grpcbox_services_simple_sup,
                    start => {grpcbox_services_simple_sup, start_link, []},
                    type => supervisor,
                    restart => permanent,
                    shutdown => 5000},
                  #{id => grpcbox_channel_sup,
                    start => {grpcbox_channel_sup, start_link, []},
                    type => supervisor,
                    restart => permanent,
                    shutdown => 5000}],
    {ok, {SupFlags, ChildSpecs}}.
