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
    %% Trapping exit so can close socket in terminate/2
    _ = process_flag(trap_exit, true),
    Port = maps:get(port, ListenOpts, 8080),
    IPAddress = maps:get(ip, ListenOpts, {0, 0, 0, 0}),
    AcceptorPoolSize = maps:get(size, PoolOpts, 10),
    SocketOpts = maps:get(socket_options, ListenOpts, [{reuseaddr, true},
                                                       {nodelay, true},
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
            %% its likely this grpcbox_socket server is restarting
            %% previously it would have bound to the port before passing control to our acceptor pool
            %% in the restart scenario, the socket process would attempt to bind again
            %% to the port and then stop, the sup would keep restarting it
            %% and we would end up breaching the restart strategy of the parent sup
            %% eventually taking down the entire tree
            %% result of which is we have no active listener and grpcbox is effectively down
            %% so now if we hit eaddrinuse, we check if our acceptor pool is already the
            %% controlling process, if so we reuse the port from its state and
            %% allow grpcbox_socket to start cleanly

            %% NOTE: acceptor_pool has a grace period for connections before it terminates
            %%       grpcbox_pool sets this to a default of 5 secs
            %%       this needs considered when deciding on related supervisor restart strategies
            %%       AND keep in mind the acceptor pool will continue accepting new connections
            %%       during this grace period

            %% Other possible fixes here include changing the grpcbox_services_sup from its
            %% rest_for_one to a one_for_all strategy.  This ensures the pool and thus the
            %% current controlling process of the socket is terminated
            %% and allows things to restart cleanly if grpcbox_socket dies
            %% the disadvantage there however is we will drop all existing grpc connections

            %% Another possible fix is to play with the restart strategy intensity and periods
            %% and ensure the top level sup doesnt get breached but...
            %% a requirement will be to ensure the grpcbox_service_sup forces a restart
            %% of grpcbox_pool and therefore the acceptor_pool process
            %% as only by doing that will be free up the socket and allow grpcbox_socket to rebind
            %% thus we end up terminating any existing grpc connections

            %% Yet another possible fix is to move the cleanup of closing the socket
            %% out of grpcbox_socket's terminate and into acceptor_pool's terminate
            %% that however puts two way co-ordination between two distinct libs
            %% which is far from ideal and in addition will also result in existing grpc connection
            %% being dropped

            %% my view is, if at all possible, its better to restart the grpcbox_socket process without
            %% impacting existing connections, the fix below allows for that, albeit a lil messy
            %% there is most likely a better solution to all of this, TODO: revisit

            %% get the current sockets in use by the acceptor pool
            %% if one is bound to our target port then reuse
            %% need to allow for possibility of multiple services, each with its own socket
            %% so we need to identify our interested socket via port number
            PoolSockets = grpcbox_pool:pool_sockets(Pool),
            MaybeHaveExistingSocket =
                lists:foldl(
                    fun({inet_tcp, {_IP, BoundPortNumber}, Socket, _SockRef}, _Acc) when BoundPortNumber =:= Port ->
                            {ok, Socket};
                        (_, Acc) ->
                            Acc
                    end, {error, eaddrinuse}, PoolSockets),
            case MaybeHaveExistingSocket of
                {ok, Socket} ->
                    MRef = monitor(port, Socket),
                    {ok, {Socket, MRef}};
                {error, Reason} ->
                    {stop, Reason}
            end;
        {error, Reason}->
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

terminate(_, {Socket, MRef}) ->
    %% Socket may already be down but need to ensure it is closed to avoid
    %% eaddrinuse error on restart
    case demonitor(MRef, [flush, info]) of
        true  -> gen_tcp:close(Socket);
        false -> ok
    end.
