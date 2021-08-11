-module(grpcbox_socket).

-behaviour(gen_server).

-export([start_link/3]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         code_change/3,
         terminate/2]).

%% public api

start_link(Pool, ListenOpts, AcceptorOpts) ->
    gen_server:start_link(?MODULE, [Pool, ListenOpts, AcceptorOpts], []).

%% gen_server api

init([Pool, ListenOpts, PoolOpts]) ->
    Port = maps:get(port, ListenOpts, 8080),
    IPAddress = maps:get(ip, ListenOpts, {0, 0, 0, 0}),
    AcceptorPoolSize = maps:get(size, PoolOpts, 10),
    SocketOpts = maps:get(socket_options, ListenOpts, [{reuseaddr, true},
                                                       {nodelay, true},
                                                       {reuseaddr, true},
                                                       {backlog, 32768},
                                                       {keepalive, true}]),
    %% Trapping exit so can close socket in terminate/2
    _ = process_flag(trap_exit, true),
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
            {stop, eaddrinuse};
        {error, Reason} ->
            {stop, Reason}
    end.

handle_call(Req, _, State) ->
    {stop, {bad_call, Req}, State}.

handle_cast(Req, State) ->
    {stop, {bad_cast, Req}, State}.

handle_info({'DOWN', MRef, port, Socket, Reason}, {Socket, MRef} = State) ->
    {stop, Reason, State};
handle_info(_, State) ->
    {noreply, State}.

code_change(_, State, _) ->
    {ok, State}.

terminate(_Reason, {Socket, MRef}) ->
    %% Socket may already be down but need to ensure it is closed to avoid
    %% eaddrinuse error on restart
    %% this takes care of that, unless of course this process is killed...
    case demonitor(MRef, [flush, info]) of
        true  -> gen_tcp:close(Socket);
        false -> ok
    end.
