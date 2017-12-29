%%%-------------------------------------------------------------------
%% @doc grpcbox public API
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_app).

-behaviour(application).

-export([start/2, stop/1]).

-include("grpcbox.hrl").

start(_StartType, _StartArgs) ->
    ets:new(?SERVICES_TAB, [public, named_table, set, {read_concurrency, true}, {keypos, 2}]),
    grpcbox_sup:start_link().

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

