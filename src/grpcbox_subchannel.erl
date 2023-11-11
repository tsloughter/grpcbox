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
               conn :: h2_stream_set:stream_set() | undefined,
               conn_pid :: pid() | undefined,
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

%% In case of unix socket transport
%% (defined as tuple {local, _UnixPath} in gen_tcp),
%% there is no standard on what the authority field value
%% should be, as HTTP/2 over UDS is not formally specified.
%% To follow other gRPC implementations' behavior,
%% the "localhost" value is used.
info_map({Scheme, {local, _UnixPath} = Host, Port, _, _}, Encoding, StatsHandler) ->
    case {Scheme, Port} of
        %% The ssl layer is not functional over unix sockets currently,
        %% and the port is strictly required to be 0 by gen_tcp.
        {http, 0} ->
            #{authority => <<"localhost">>,
              scheme => <<"http">>,
              encoding => Encoding,
              stats_handler => StatsHandler};
        _ ->
            error({badarg, [Scheme, Host, Port]})
    end;
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
handle_event(info, {'EXIT', Pid, _}, Data=#data{conn_pid=Pid}) ->
    {next_state, disconnected, Data#data{conn=undefined, conn_pid=undefined}};
handle_event(info, {'EXIT', _, econnrefused}, #data{conn=undefined, conn_pid=undefined}) ->
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
terminate(Reason, _State, #data{conn_pid=Pid,
                                 endpoint=Endpoint,
                                 channel=Channel}) ->
    exit(Pid, Reason),
    gproc_pool:disconnect_worker(Channel, Endpoint),
    gproc_pool:remove_worker(Channel, Endpoint),
    ok.

connect(Data=#data{conn=undefined,
                   endpoint={Transport, Host, Port, SSLOptions, ConnectionSettings}}, From, Actions) ->
    case h2_client:start_link(Transport, Host, Port, options(Transport, SSLOptions),
                              ConnectionSettings#{garbage_on_end => true,
                                                  stream_callback_mod => grpcbox_client_stream}) of
        {ok, Conn} ->
            Pid = h2_stream_set:connection(Conn),
            {next_state, ready, Data#data{conn=Conn, conn_pid=Pid}, Actions};
        {error, _}=Error ->
            {next_state, disconnected, Data#data{conn=undefined}, [{reply, From, Error}]}
    end;
connect(Data=#data{conn=Conn, conn_pid=Pid}, From, Actions) when is_pid(Pid) ->
    h2_connection:stop(Conn),
    connect(Data#data{conn=undefined, conn_pid=undefined}, From, Actions).

options(https, Options) ->
    [{client_preferred_next_protocols, {client, [<<"h2">>]}} | Options];
options(http, Options) ->
    Options.
