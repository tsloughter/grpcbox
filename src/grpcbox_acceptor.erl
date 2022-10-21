-module(grpcbox_acceptor).

-behaviour(acceptor).

-export([acceptor_init/3,
         acceptor_continue/3,
         acceptor_terminate/2]).

acceptor_init(_, LSocket, {PoolName, Transport, ServerOpts, ChatterboxOpts, SslOpts}) ->
    % monitor listen socket to gracefully close when it closes
    MRef = monitor(port, LSocket),
    {ok, {Transport, MRef, PoolName, ServerOpts, ChatterboxOpts, SslOpts}}.

acceptor_continue(_PeerName, Socket, {ssl, _MRef, PoolName, ServerOpts, ChatterboxOpts, SslOpts}) ->
    {ok, AcceptSocket} = ssl:handshake(Socket, SslOpts),
    case ssl:negotiated_protocol(AcceptSocket) of
        {ok, <<"h2">>} ->
            MaxConns = maps:get(max_connections, ServerOpts, unlimited),
            case connection_allowed(PoolName, MaxConns) of
                true ->
                    h2_connection:become({ssl, AcceptSocket}, chatterbox:settings(server, ServerOpts), ChatterboxOpts);
                false ->
                    exit(max_connections_exceeded)
            end;
        _ ->
            exit(bad_negotiated_protocol)
    end;

acceptor_continue(_PeerName, Socket, {gen_tcp, _MRef, PoolName, ServerOpts, ChatterboxOpts, _SslOpts}) ->
    MaxConns = maps:get(max_connections, ServerOpts, unlimited),
    case connection_allowed(PoolName, MaxConns) of
        true ->
            h2_connection:become({gen_tcp, Socket}, chatterbox:settings(server, ServerOpts), ChatterboxOpts);
        false ->
            exit(max_connections_exceeded)
    end.

acceptor_terminate(Reason, _) ->
    % Something went wrong. Either the acceptor_pool is terminating or the
    % accept failed.
    exit(Reason).

connection_allowed(_PoolName, unlimited) ->
    true;
connection_allowed(PoolName, MaxConns) ->
    grpcbox_pool:connection_count(PoolName) =< MaxConns .

