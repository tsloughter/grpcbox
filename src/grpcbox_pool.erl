-module(grpcbox_pool).

-behaviour(acceptor_pool).

-export([start_link/2,
         accept_socket/2]).

-export([init/1]).

%% public api

start_link(ChatterboxOpts, ListenOpts) ->
    acceptor_pool:start_link({local, grpcbox_pool}, ?MODULE, [ChatterboxOpts, ListenOpts]).

accept_socket(Socket, Acceptors) ->
    acceptor_pool:accept_socket(grpcbox_pool, Socket, Acceptors).

%% acceptor_pool api

init([ChatterboxOpts, ListenOpts]) ->
    {Transport, SslOpts} = case ListenOpts of
                               #{ssl := true,
                                 keyfile := KeyFile,
                                 certfile := CertFile,
                                cacertfile := CACertFile} ->
                                   {ssl, [{keyfile, KeyFile},
                                          {certfile, CertFile},
                                          {honor_cipher_order, false},
                                          {cacertfile, CACertFile},
                                          {fail_if_no_peer_cert, true},
                                          {verify, verify_peer},
                                          {versions, ['tlsv1.2']},
                                          {next_protocols_advertised, [<<"h2">>]}]};
                               _ ->
                                   {gen_tcp, []}
                           end,

    Conn = #{id => grpcbox_acceptor,
             start => {grpcbox_acceptor, {Transport, ChatterboxOpts, SslOpts}, []},
             grace => 5000},
    {ok, {#{}, [Conn]}}.
