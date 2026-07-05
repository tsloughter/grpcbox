-module(grpcbox_acceptor).

-behaviour(acceptor).

-export([acceptor_init/3,
         acceptor_continue/3,
         acceptor_terminate/2]).

acceptor_init(_, LSocket, {Transport, ServerSettings, StreamOpts, SslOpts}) ->
    % monitor listen socket to gracefully close when it closes
    MRef = monitor(port, LSocket),
    {ok, {Transport, MRef, ServerSettings, StreamOpts, SslOpts}}.

acceptor_continue(_PeerName, Socket, {ssl, _MRef, ServerSettings, StreamOpts, SslOpts}) ->
    {ok, AcceptSocket} = ssl:handshake(Socket, SslOpts),
    case ssl:negotiated_protocol(AcceptSocket) of
        {ok, <<"h2">>} ->
            become_connection(ssl, AcceptSocket, ServerSettings,
                              StreamOpts#{peercert => peercert(AcceptSocket)});
        _ ->
            exit(bad_negotiated_protocol)
    end;
acceptor_continue(_PeerName, Socket, {gen_tcp, _MRef, ServerSettings, StreamOpts, _SslOpts}) ->
    become_connection(gen_tcp, Socket, ServerSettings, StreamOpts#{peercert => undefined}).

acceptor_terminate(Reason, _) ->
    % Something went wrong. Either the acceptor_pool is terminating or the
    % accept failed.
    exit(Reason).

%% Internal

peercert(Socket) ->
    case ssl:peercert(Socket) of
        {ok, Cert} ->
            Cert;
        {error, _} ->
            undefined
    end.

%% become the owner of an h2 connection on the accepted socket. The
%% connection process is linked and owns the socket, this process receives
%% new request events and spawns a grpcbox_stream per stream.
become_connection(Transport, Socket, ServerSettings, StreamOpts) ->
    process_flag(trap_exit, true),
    {ok, Conn} = h2_connection:start_link(server, Socket, self(),
                                          #{settings => ServerSettings}),
    case controlling_process(Transport, Socket, Conn) of
        ok ->
            case h2_connection:activate(Conn) of
                ok ->
                    connection_loop(Conn, parent(), StreamOpts, #{});
                {error, _} ->
                    %% the peer disconnected right after the accept
                    close_connection(Transport, Socket, Conn),
                    exit(normal)
            end;
        {error, _} ->
            close_connection(Transport, Socket, Conn),
            exit(normal)
    end.

controlling_process(ssl, Socket, Pid) ->
    ssl:controlling_process(Socket, Pid);
controlling_process(gen_tcp, Socket, Pid) ->
    gen_tcp:controlling_process(Socket, Pid).

close_connection(Transport, Socket, Conn) ->
    try h2_connection:close(Conn) catch _:_ -> ok end,
    case Transport of
        ssl -> ssl:close(Socket);
        gen_tcp -> gen_tcp:close(Socket)
    end.

%% the acceptor process is spawned by the acceptor_pool with proc_lib
parent() ->
    case get('$ancestors') of
        [Parent | _] when is_pid(Parent) ->
            Parent;
        _ ->
            undefined
    end.

connection_loop(Conn, Parent, StreamOpts, Streams) ->
    receive
        {h2, Conn, {request, StreamId, Method, Path, Headers}} ->
            ReqHeaders = [{<<":method">>, Method}, {<<":path">>, Path} | Headers],
            case grpcbox_stream:start_link(Conn, StreamId, ReqHeaders, StreamOpts) of
                {ok, Pid} ->
                    connection_loop(Conn, Parent, StreamOpts, Streams#{Pid => StreamId});
                _ ->
                    _ = h2:cancel(Conn, StreamId, internal_error),
                    connection_loop(Conn, Parent, StreamOpts, Streams)
            end;
        {'EXIT', Conn, Reason} ->
            exit(Reason);
        {'EXIT', Pid, Reason} when is_map_key(Pid, Streams) ->
            {StreamId, Streams1} = maps:take(Pid, Streams),
            case Reason of
                normal ->
                    ok;
                {shutdown, _} ->
                    ok;
                _ ->
                    %% stream handler crashed before completing the rpc,
                    %% reset the stream so the client doesn't wait for
                    %% trailers that will never come
                    _ = h2:cancel(Conn, StreamId, internal_error)
            end,
            connection_loop(Conn, Parent, StreamOpts, Streams1);
        {'EXIT', Parent, Reason} ->
            %% acceptor pool is going away, take the connection down with us
            try h2_connection:close(Conn) catch _:_ -> ok end,
            exit(Reason);
        {'EXIT', _Pid, shutdown} ->
            %% acceptor pool is shutting down
            try h2_connection:close(Conn) catch _:_ -> ok end,
            exit(shutdown);
        _ ->
            connection_loop(Conn, Parent, StreamOpts, Streams)
    end.
