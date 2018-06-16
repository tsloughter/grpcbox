-module(grpcbox_acceptor).

-behaviour(acceptor).

-export([acceptor_init/3,
         acceptor_continue/3,
         acceptor_terminate/2]).

acceptor_init(_, LSocket, {Transport, ServerOpts, ChatterboxOpts, SslOpts}) ->
    % monitor listen socket to gracefully close when it closes
    MRef = monitor(port, LSocket),
    {ok, {Transport, MRef, ServerOpts, ChatterboxOpts, SslOpts}}.

acceptor_continue(_PeerName, Socket, {ssl, _MRef, ServerOpts, ChatterboxOpts, SslOpts}) ->
    {ok, AcceptSocket} = ssl:handshake(Socket, SslOpts),
    case ssl:negotiated_protocol(AcceptSocket) of
        {ok, <<"h2">>} ->
            h2_connection:become({ssl, AcceptSocket}, ServerOpts, ChatterboxOpts);
        _ ->
            exit(bad_negotiated_protocol)
    end;
acceptor_continue(_PeerName, Socket, {gen_tcp, _MRef, ServerOpts, ChatterboxOpts, _SslOpts}) ->
    h2_connection:become({gen_tcp, Socket}, ServerOpts, ChatterboxOpts).

acceptor_terminate(Reason, _) ->
    % Something went wrong. Either the acceptor_pool is terminating or the
    % accept failed.
    exit(Reason).
