-module(grpcbox_channel).

-behaviour(gen_statem).

-export([start_link/3,
         is_ready/1,
         get/3,
         pick/2,
         pick/3,
         add_endpoints/2,
         remove_endpoints/3,
         stop/1,
         stop/2]).
-export([init/1,
         callback_mode/0,
         terminate/3,
         connected/3,
         idle/3]).

-include("grpcbox.hrl").

-define(CHANNEL(Name), {via, gproc, {n, l, {?MODULE, Name}}}).

-type t() :: any().
-type name() :: t().
-type transport() :: http | https.
-type endpoint_options() :: [ssl:ssl_option() |
                             {connect_timeout, integer()} |
                             {tcp_user_timeout, integer()}].
-type host() :: inet:ip_address() | inet:hostname().
-type endpoint() :: {transport(), host(), inet:port_number(), endpoint_options()}.

-type options() :: #{balancer => load_balancer(),
                     encoding => gprcbox:encoding(),
                     unary_interceptor => grpcbox_client:unary_interceptor(),
                     stream_interceptor => grpcbox_client:stream_interceptor(),
                     stats_handler => module(),
                     sync_start => boolean()}.
-type load_balancer() :: round_robin | random | hash | direct | claim.
-export_type([t/0,
              name/0,
              options/0,
              endpoint/0]).

-record(data, {endpoints :: [endpoint()],
               pool :: atom(),
               resolver :: module(),
               balancer :: grpcbox:balancer(),
               encoding :: grpcbox:encoding(),
               interceptors :: #{unary_interceptor => grpcbox_client:unary_interceptor(),
                                 stream_interceptor => grpcbox_client:stream_interceptor()}
                             | undefined,
               stats_handler :: module() | undefined,
               refresh_interval :: timer:time()}).

-spec start_link(name(), [endpoint()], options()) -> {ok, pid()} | ignore | {error, term()}.
start_link(Name, Endpoints, Options) ->
    gen_statem:start_link(?CHANNEL(Name), ?MODULE, [Name, Endpoints, Options], []).

-spec is_ready(name()) -> boolean().
is_ready(Name) ->
    gen_statem:call(?CHANNEL(Name), is_ready).

-spec get(name(), unary | stream, term()) ->
    {ok, {pid(), grpcbox_client:interceptor() | undefined}} |
    {error, undefined_channel | not_found_endpoint}.
get(Name, CallType, Key) ->
    case lists:keyfind(Key, 1, gproc_pool:active_workers(Name)) of
        {_, Pid} -> {ok, {Pid, interceptor(Name, CallType)}};
        false -> {error, not_found_endpoint}
    end.


%% @doc Picks a subchannel from a pool using the configured strategy.
-spec pick(name(), unary | stream) ->
    {ok, {pid(), grpcbox_client:interceptor() | undefined}} |
    {error, undefined_channel | no_endpoints}.
pick(Name, CallType) ->
    pick(Name, CallType, undefined).

%% @doc Picks a subchannel from a pool using the configured strategy.
-spec pick(name(), unary | stream, term() | undefined) ->
    {ok, {pid(), grpcbox_client:interceptor() | undefined}} |
    {error, undefined_channel | no_endpoints}.
pick(Name, CallType, Key) ->
    try
        case pick_worker(Name, Key) of
            false -> {error, no_endpoints};
            Pid when is_pid(Pid) ->
                {ok, {Pid, interceptor(Name, CallType)}}
        end
    catch
        error:badarg ->
            {error, undefined_channel}
    end.

pick_worker(Name, undefined) ->
    gproc_pool:pick_worker(Name);
pick_worker(Name, Key) ->
    gproc_pool:pick_worker(Name, Key).

add_endpoints(Name, Endpoints) ->
    gen_statem:call(?CHANNEL(Name), {add_endpoints, Endpoints}).

remove_endpoints(Name, Endpoints, Reason) ->
    gen_statem:call(?CHANNEL(Name), {remove_endpoints, Endpoints, Reason}).

-spec interceptor(name(), unary | stream) -> grpcbox_client:interceptor() | undefined.
interceptor(Name, CallType) ->
    case ets:lookup(?CHANNELS_TAB, {Name, CallType}) of
        [] ->
            undefined;
        [{_, I}] ->
            I
    end.

stop(Name) ->
    stop(Name, {shutdown, force_delete}).
stop(Name, Reason) ->
    gen_statem:stop(?CHANNEL(Name), Reason, infinity).

init([Name, Endpoints, Options]) ->
    process_flag(trap_exit, true),
    BalancerType = maps:get(balancer, Options, round_robin),
    Encoding = maps:get(encoding, Options, identity),
    StatsHandler = maps:get(stats_handler, Options, undefined),

    insert_interceptors(Name, Options),

    gproc_pool:new(Name, BalancerType, [{size, length(Endpoints)},
                                        {auto_size, true}]),
    gproc_pool:new({Name, active}, BalancerType, [{size, length(Endpoints)},
                                        {auto_size, true}]),
    Data = #data{
        pool = Name,
        encoding = Encoding,
        stats_handler = StatsHandler,
        endpoints = lists:usort(Endpoints)
    },
    case maps:get(sync_start, Options, false) of
        false ->
            {ok, idle, Data, [{next_event, internal, connect}]};
        true ->
            start_workers(Name, StatsHandler, Encoding, Endpoints),
            {ok, connected, Data}
    end.

callback_mode() ->
    state_functions.

connected({call, From}, is_ready, _Data) ->
    {keep_state_and_data, [{reply, From, true}]};
connected({call, From}, {add_endpoints, Endpoints},
            Data=#data{pool=Pool,
                       stats_handler=StatsHandler,
                       encoding=Encoding,
                       endpoints=TotalEndpoints}) ->
    NewEndpoints = lists:subtract(Endpoints, TotalEndpoints),
    NewTotalEndpoints = lists:umerge(TotalEndpoints, Endpoints),
    start_workers(Pool, StatsHandler, Encoding, NewEndpoints),
    {keep_state, Data#data{endpoints=NewTotalEndpoints}, [{reply, From, ok}]};
connected({call, From}, {remove_endpoints, Endpoints, Reason},
            Data=#data{pool=Pool, endpoints=TotalEndpoints}) ->

    NewEndpoints = sets:to_list(sets:intersection(sets:from_list(Endpoints),
                                sets:from_list(TotalEndpoints))),
    NewTotalEndpoints = lists:subtract(TotalEndpoints, Endpoints),
    stop_workers(Pool, NewEndpoints, Reason),
    {keep_state, Data#data{endpoints = NewTotalEndpoints}, [{reply, From, ok}]};
connected(EventType, EventContent, Data) ->
    handle_event(EventType, EventContent, Data).

idle(internal, connect, Data=#data{pool=Pool,
                                   stats_handler=StatsHandler,
                                   encoding=Encoding,
                                   endpoints=Endpoints}) ->

    start_workers(Pool, StatsHandler, Encoding, Endpoints),
    {next_state, connected, Data};
idle({call, From}, is_ready, _Data) ->
    {keep_state_and_data, [{reply, From, false}]};
idle(EventType, EventContent, Data) ->
    handle_event(EventType, EventContent, Data).

handle_event(_, _, Data) ->
    {keep_state, Data}.

terminate({shutdown, force_delete}, _State, #data{pool=Name}) ->
    gproc_pool:force_delete(Name),
    gproc_pool:force_delete({Name, active});
terminate(Reason, _State, #data{pool=Name}) ->
    [grpcbox_subchannel:stop(Pid, Reason) || {_Channel, Pid} <- gproc_pool:active_workers(Name)],
    gproc_pool:delete(Name),
    gproc_pool:delete({Name, active}),
    ok.

insert_interceptors(Name, Interceptors) ->
    insert_unary_interceptor(Name, Interceptors),
    insert_stream_interceptor(Name, stream_interceptor, Interceptors).

insert_unary_interceptor(Name, Interceptors) ->
    case maps:get(unary_interceptor, Interceptors, undefined) of
        undefined ->
            ok;
        {Interceptor, Arg} ->
            ets:insert(?CHANNELS_TAB, {{Name, unary}, Interceptor(Arg)});
        Interceptor ->
            ets:insert(?CHANNELS_TAB, {{Name, unary}, Interceptor})
    end.

insert_stream_interceptor(Name, _Type, Interceptors) ->
    case maps:get(stream_interceptor, Interceptors, undefined) of
        undefined ->
            ok;
        {Interceptor, Arg} ->
            ets:insert(?CHANNELS_TAB, {{Name, stream}, Interceptor(Arg)});
        Interceptor when is_atom(Interceptor) ->
            ets:insert(?CHANNELS_TAB, {{Name, stream}, #{new_stream => fun Interceptor:new_stream/6,
                                                         send_msg => fun Interceptor:send_msg/3,
                                                         recv_msg => fun Interceptor:recv_msg/3}});
        Interceptor=#{new_stream := _,
                      send_msg := _,
                      recv_msg := _} ->
            ets:insert(?CHANNELS_TAB, {{Name, stream}, Interceptor})
    end.

start_workers(Pool, StatsHandler, Encoding, Endpoints) ->
    [begin
        gproc_pool:add_worker(Pool, Endpoint),
        gproc_pool:add_worker({Pool, active}, Endpoint),
        {ok, Pid} = grpcbox_subchannel:start_link(Endpoint,
                                                    Pool, Endpoint, Encoding, StatsHandler),
        Pid
     end || Endpoint <- Endpoints].

stop_workers(Pool, Endpoints, Reason) ->
    [begin
        case gproc_pool:whereis_worker(Pool, Endpoint) of
            undefined -> ok;
            Pid -> grpcbox_subchannel:stop(Pid, Reason)
        end
     end || Endpoint <- Endpoints].
