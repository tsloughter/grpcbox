-module(grpcbox_socket).

-behaviour(gen_server).

-export([start_link/3]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         code_change/3,
         terminate/2]).

-record(state, {
    pool,
    listen_opts,
    pool_opts,
    socket,
    mref
}).

%% public api
start_link(Pool, ListenOpts, AcceptorOpts) ->
    gen_server:start_link(?MODULE, [Pool, ListenOpts, AcceptorOpts], []).

%% gen_server api

init([Pool, ListenOpts, PoolOpts]) ->
    {ok, #state{pool = Pool, pool_opts = PoolOpts, listen_opts = ListenOpts}, 0}.

handle_call(Req, _, State) ->
    {stop, {bad_call, Req}, State}.

handle_cast(Req, State) ->
    {stop, {bad_cast, Req}, State}.
handle_info(timeout, State) ->
    case start_listener(State) of
        {ok, {Socket, MRef}} ->
            {noreply, State#state{socket = Socket, mref = MRef}};
        _ ->
            erlang:send_after(5000, self(), timeout),
            {noreply, State}
    end;
handle_info({'DOWN', MRef, port, Socket, _Reason}, #state{mref = MRef, socket = Socket} = State) ->
    catch gen_tcp:close(Socket),
    erlang:send_after(5000, self(), timeout),
    {noreply, State};
handle_info(_Msg, State) ->
    {noreply, State}.

code_change(_, State, _) ->
    {ok, State}.

terminate(_Reason, #state{mref = MRef, socket = Socket} = _State) ->
    %% Socket may already be down but need to ensure it is closed to avoid
    %% eaddrinuse error on restart
    %% this takes care of that, unless of course this process is killed...
    case demonitor(MRef, [flush, info]) of
        true  -> gen_tcp:close(Socket);
        false -> ok
    end.

%% ------------------------------------------------------------------
%% Internal functions
%% ------------------------------------------------------------------
start_listener(#state{
        pool = Pool,
        listen_opts = ListenOpts,
        pool_opts = PoolOpts} = _State) ->
    Port = maps:get(port, ListenOpts, 8080),
    IPAddress = maps:get(ip, ListenOpts, {0, 0, 0, 0}),
    AcceptorPoolSize = maps:get(size, PoolOpts, 10),
    SocketOpts = maps:get(socket_options, ListenOpts, [{reuseaddr, true},
                                                       {nodelay, true},
                                                       {reuseaddr, true},
                                                       {backlog, 32768},
                                                       {keepalive, true}]),

    Opts = [{active, false}, {mode, binary}, {packet, raw}, {ip, IPAddress} | SocketOpts],
    case gen_tcp:listen(Port, Opts) of
        {ok, Socket} ->
            %% acceptor could close the socket if there is a problem
            MRef = monitor(port, Socket),
            {ok, _} = grpcbox_pool:accept_socket(Pool, Socket, AcceptorPoolSize),
            {ok, {Socket, MRef}};
        {error, eaddrinuse} ->
            %% our desired port is already in use
            %% its likely this grpcbox_socket server has been killed ( for reason unknown ) and is restarting
            %% previously it would have bound to the port before passing control to our acceptor pool
            %% the socket remains open
            %% in the restart scenario, the socket process would attempt to bind again
            %% to the port and then stop, the sup would keep restarting it
            %% and we would end up breaching the restart strategy of the parent sup
            %% eventually taking down the entire tree
            %% result of which is we have no active listener and grpcbox is effectively down
            %% so now if we hit eaddrinuse, we check if our acceptor pool using it
            %% if so we close the port here and stop this process
            %% NOTE: issuing stop in init wont trigger terminate and so cant rely on
            %%       the socket being closed there
            %% This allows the sup to restart things cleanly
            %% We could try to reuse the exising port rather than closing it
            %% but side effects were encountered there, so deliberately avoiding

            %% NOTE: acceptor_pool has a grace period for connections before it terminates
            %%       grpcbox_pool sets this to a default of 5 secs
            %%       this needs considered when deciding on related supervisor restart strategies
            %%       AND keep in mind the acceptor pool will continue accepting new connections
            %%       during this grace period

            %% get the current sockets in use by the acceptor pool
            %% if one is bound to our target port then close it
            %% need to allow for possibility of multiple services, each with its own socket
            %% so we need to identify our interested socket via port number
            PoolSockets = grpcbox_pool:pool_sockets(Pool),
            MaybeHaveExistingSocket =
                lists:foldl(
                    fun({inet_tcp, {_IP, BoundPortNumber}, Socket, _SockRef}, _Acc) when BoundPortNumber =:= Port ->
                            {ok, Socket};
                        (_, Acc) ->
                            Acc
                    end, socket_not_found, PoolSockets),
            case MaybeHaveExistingSocket of
                {ok, Socket} ->
                    gen_tcp:close(Socket);
                socket_not_found ->
                    noop
            end,
            {error, eaddrinuse};
        {error, Reason} ->
            {error, Reason}
    end.
