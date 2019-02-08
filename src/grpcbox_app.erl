%%%-------------------------------------------------------------------
%% @doc grpcbox public API
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_app).

-behaviour(application).

-export([start/2, stop/1]).

-include("grpcbox.hrl").

start(_StartType, _StartArgs) ->
    {ok, Pid} = grpcbox_sup:start_link(),
    case application:get_env(grpcbox, client) of
        {ok, #{channels := Channels}} ->
            [grpcbox_channel_sup:start_child(Name, Endpoints, Options)
             || {Name, Endpoints, Options} <- Channels];
        _ ->
            ok
    end,

    ServerOpts = application:get_env(grpcbox, servers, []),
    maybe_start_server(ServerOpts),

    {ok, Pid}.

stop(_State) ->
    ok.

%%

maybe_start_server([]) ->
    ok;
maybe_start_server([ServerOpts | Tail]) ->
    grpcbox_services_simple_sup:start_child(ServerOpts),
    maybe_start_server(Tail).
