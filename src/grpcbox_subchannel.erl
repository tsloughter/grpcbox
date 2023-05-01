-module(grpcbox_subchannel).

-behaviour(gen_statem).

-export([start_link/5,
         conn/1,
         conn/2,
         stop/2]).
-export([init/1,
         callback_mode/0,
         terminate/3,

         %% states
         ready/3,
         disconnected/3]).

-record(data, {endpoint :: grpcbox_channel:endpoint(),
               channel :: grpcbox_channel:t(),
               info :: #{authority := binary(),
                         scheme := binary(),
                         encoding := grpcbox:encoding(),
                         stats_handler := module() | undefined
                        },
               conn :: pid() | undefined,
               idle_interval :: timer:time()}).

start_link(Name, Channel, Endpoint, Encoding, StatsHandler) ->
    gen_statem:start_link(?MODULE, [Name, Channel, Endpoint, Encoding, StatsHandler], []).

conn(Pid) ->
    conn(Pid, infinity).
conn(Pid, Timeout) ->
    try
        gen_statem:call(Pid, conn, Timeout)
    catch
        exit:{timeout, _} -> {error, timeout}
    end.

stop(Pid, Reason) ->
    gen_statem:stop(Pid, Reason, infinity).

init([Name, Channel, Endpoint, Encoding, StatsHandler]) ->
    process_flag(trap_exit, true),
    gproc_pool:connect_worker(Channel, Name),
    {ok, disconnected, #data{conn=undefined,
                             info=info_map(Endpoint, Encoding, StatsHandler),
                             endpoint=Endpoint,
                             channel=Channel}}.

info_map({http, Host, 80, _, _}, Encoding, StatsHandler) ->
    #{authority => list_to_binary(Host),
      scheme => <<"http">>,
      encoding => Encoding,
      stats_handler => StatsHandler};
info_map({https, Host, 443, _, _}, Encoding, StatsHandler) ->
    #{authority => list_to_binary(Host),
      scheme => <<"https">>,
      encoding => Encoding,
      stats_handler => StatsHandler};
info_map({Scheme, Host, Port, _, _}, Encoding, StatsHandler) ->
    #{authority => list_to_binary(Host ++ ":" ++ integer_to_list(Port)),
      scheme => atom_to_binary(Scheme, utf8),
      encoding => Encoding,
      stats_handler => StatsHandler}.

callback_mode() ->
    state_functions.

ready({call, From}, conn, #data{conn=Conn,
                                info=Info}) ->
    {keep_state_and_data, [{reply, From, {ok, Conn, Info}}]};
ready(EventType, EventContent, Data) ->
    handle_event(EventType, EventContent, Data).

disconnected({call, From}, conn, Data) ->
    connect(Data, From, [postpone]);
disconnected(EventType, EventContent, Data) ->
    handle_event(EventType, EventContent, Data).

handle_event({call, From}, info, #data{info=Info}) ->
    {keep_state_and_data, [{reply, From, Info}]};
handle_event(info, {'EXIT', Pid, _}, Data=#data{conn=Pid}) ->
    {next_state, disconnected, Data#data{conn=undefined}};
handle_event(info, {'EXIT', _, econnrefused}, #data{conn=undefined}) ->
    keep_state_and_data;
handle_event({call, From}, shutdown, _) ->
    {stop_and_reply, normal, {reply, From, ok}};
handle_event(_, _, _) ->
    keep_state_and_data.

terminate(_Reason, _State, #data{conn=undefined,
                                 endpoint=Endpoint,
                                 channel=Channel}) ->
    gproc_pool:disconnect_worker(Channel, Endpoint),
    gproc_pool:remove_worker(Channel, Endpoint),
    ok;
terminate(normal, _State, #data{conn=Pid,
                                 endpoint=Endpoint,
                                 channel=Channel}) ->
    h2_connection:stop(Pid),
    gproc_pool:disconnect_worker(Channel, Endpoint),
    gproc_pool:remove_worker(Channel, Endpoint),
    ok;
terminate(Reason, _State, #data{conn=Pid,
                                 endpoint=Endpoint,
                                 channel=Channel}) ->
    exit(Pid, Reason),
    gproc_pool:disconnect_worker(Channel, Endpoint),
    gproc_pool:remove_worker(Channel, Endpoint),
    ok.

connect(Data=#data{conn=undefined,
                   endpoint={Transport, Host, Port, SocketOptions, SSLOptions}}, From, Actions) ->
    case h2_client:start_link(Transport, Host, Port, SocketOptions, ssl_options(Transport, SSLOptions),
                             #{garbage_on_end => true,
                               stream_callback_mod => grpcbox_client_stream}) of
        {ok, Pid} ->
            {next_state, ready, Data#data{conn=Pid}, Actions};
        {error, _}=Error ->
            {next_state, disconnected, Data#data{conn=undefined}, [{reply, From, Error}]}
    end;
connect(Data=#data{conn=Pid}, From, Actions) when is_pid(Pid) ->
    h2_connection:stop(Pid),
    connect(Data#data{conn=undefined}, From, Actions).

ssl_options(https, Options) ->
    [{client_preferred_next_protocols, {client, [<<"h2">>]}} | Options];
ssl_options(http, Options) ->
    Options.
