-module(grpcbox_subchannel).

-behaviour(gen_statem).

-export([start_link/5,
         conn/1]).
-export([init/1,
         callback_mode/0,
         terminate/3,

         %% states
         ready/3,
         transient_failure/3,
         idle/3,
         shutdown/3]).

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
    gen_statem:call(Pid, conn).

init([Name, Channel, Endpoint, Encoding, StatsHandler]) ->
    process_flag(trap_exit, true),
    gproc_pool:connect_worker(Channel, Name),
    {ok, idle, #data{conn=undefined,
                     info=info_map(Endpoint, Encoding, StatsHandler),
                     endpoint=Endpoint,
                     channel=Channel}}.

info_map({http, Host, 80, _}, Encoding, StatsHandler) ->
    #{authority => list_to_binary(Host),
      scheme => <<"http">>,
      encoding => Encoding,
      stats_handler => StatsHandler};
info_map({https, Host, 443, _}, Encoding, StatsHandler) ->
    #{authority => list_to_binary(Host),
      scheme => <<"https">>,
      encoding => Encoding,
      stats_handler => StatsHandler};
info_map({Scheme, Host, Port, _}, Encoding, StatsHandler) ->
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

transient_failure({call, From}, conn, Data) ->
    connect(Data, From, [postpone]);
transient_failure(EventType, EventContent, Data) ->
    handle_event(EventType, EventContent, Data).

idle({call, From}, conn, Data) ->
    connect(Data, From, [postpone]);
idle(EventType, EventContent, Data) ->
    handle_event(EventType, EventContent, Data).

shutdown({call, From}, conn, _) ->
    {keep_state_and_data, [{reply, From, {error, shutting_down}}]};
shutdown(EventType, EventContent, Data) ->
    handle_event(EventType, EventContent, Data).

handle_event({call, From}, info, #data{info=Info}) ->
    {keep_state_and_data, [{reply, From, Info}]};
handle_event(info, {'EXIT', Pid, econnrefused}, Data=#data{conn=Pid}) ->
    {next_state, idle, Data#data{conn=undefined}};
handle_event(info, {'EXIT', _, econnrefused}, Data=#data{conn=undefined}) ->
    {next_state, idle, Data#data{conn=undefined}};
handle_event(_, _, _) ->
    keep_state_and_data.

terminate(_Reason, _State, #data{endpoint=Endpoint,
                                 channel=Channel}) ->
    gproc_pool:disconnect_worker(Channel, Endpoint),
    gproc_pool:remove_worker(Channel, Endpoint),
    ok.

connect(Data=#data{conn=undefined,
                   endpoint={Transport, Host, Port, SSLOptions}}, From, Actions) ->
    case h2_client:start_link(Transport, Host, Port, options(Transport, SSLOptions),
                              #{stream_callback_mod => grpcbox_client_stream}) of
        {ok, Pid} ->
            {next_state, ready, Data#data{conn=Pid}, Actions};
        {error, _}=Error ->
            {keep_state_and_data, [{reply, From, Error}]}
    end;
connect(Data=#data{conn=Pid}, From, Actions) when is_pid(Pid) ->
    h2_connection:stop(Pid),
    connect(Data#data{conn=undefined}, From, Actions).

options(https, Options) ->
    [{client_preferred_next_protocols, {client, [<<"h2">>]}} | Options];
options(http, Options) ->
    Options.
