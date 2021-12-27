%%%-------------------------------------------------------------------
%% @doc grpcbox client connection supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_channel_sup).

-behaviour(supervisor).

-export([start_link/0,
         channel_spec/3,
         start_child/3]).
-export([init/1]).

-include("grpcbox.hrl").

-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%% @doc Start a channel under the grpcbox channel supervisor.
-spec start_child(atom(), [grpcbox_channel:endpoint()], grpcbox_channel:options()) -> supervisor:startchild_ret().
start_child(Name, Endpoints, Options) ->
    supervisor:start_child(?SERVER, [Name, Endpoints, Options]).

%% @doc Create a default child spec for starting a channel
-spec channel_spec(atom(), [grpcbox_channel:endpoint()], grpcbox_channel:options())
                  -> supervisor:child_spec().
channel_spec(Name, Endpoints, Options) ->
    #{id => grpcbox_channel,
      start => {grpcbox_channel, start_link, [Name, Endpoints, Options]},
      type => worker}.

init(_Args) ->
    ets:new(?CHANNELS_TAB, [named_table, set, public, {read_concurrency, true}]),

    SupFlags = #{strategy => simple_one_for_one,
                 intensity => 5,
                 period => 10},
    ChildSpecs = [#{id => grpcbox_channel,
                    start => {grpcbox_channel, start_link, []},
                    type => worker,
                    restart => transient,
                    shutdown => 1000}
                 ],
    {ok, {SupFlags, ChildSpecs}}.
