-module(grpcbox_acceptor).

-behaviour(acceptor).

-export([acceptor_init/3,
         acceptor_continue/3,
         acceptor_terminate/2]).

acceptor_init(_, LSocket, {Transport, ChatterboxOpts, SslOpts}) ->
    % monitor listen socket to gracefully close when it closes
    MRef = monitor(port, LSocket),
    {ok, {Transport, MRef, ChatterboxOpts, SslOpts}}.

acceptor_continue(_PeerName, Socket, {ssl, _MRef, ChatterboxOpts, SslOpts}) ->
    {ok, AcceptSocket} = ssl:ssl_accept(Socket, SslOpts),
    case ssl:negotiated_protocol(AcceptSocket) of
        {ok, <<"h2">>} ->
            h2_connection:become({ssl, AcceptSocket}, ChatterboxOpts);
        _ ->
            exit(bad_negotiated_protocol)
    end;
acceptor_continue(_PeerName, Socket, {gen_tcp, _MRef, ChatterboxOpts, _SslOpts}) ->
    h2_connection:become({gen_tcp, Socket}, ChatterboxOpts).

acceptor_terminate(Reason, _) ->
    % Something went wrong. Either the acceptor_pool is terminating or the
    % accept failed.
    exit(Reason).
