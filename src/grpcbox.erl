%%%-------------------------------------------------------------------
%% @doc grpc client
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox).

-export([start_server/0,
         start_server/1]).

-include_lib("chatterbox/include/http2.hrl").

-type encoding() :: identity | gzip | deflate | snappy | atom().
-type metadata() :: #{headers := grpcbox_metadata:t(),
                      trailers := grpcbox_metadata:t()}.

-type server_opts() :: #{server_opts => settings(), %% TODO: change this in chatterbox to be under a module
                         grpc_opts => #{service_protos := [module()]},
                         listen_opts => #{port => inet:port_number(),
                                          ip => inet:ip_address(),
                                          socket_options => [gen_tcp:option()]},
                         pool_opts => #{size => integer()},
                         transport_opts => #{ssl => boolean(),
                                             keyfile => file:filename_all(),
                                             certfile => file:filename_all(),
                                             cacertfile => file:filename_all()}}.

-export_type([metadata/0,
              server_opts/0,
              encoding/0]).

start_server() ->
    GrpcOpts = application:get_env(grpcbox, grpc_opts, #{}),
    ServerOpts = application:get_env(grpcbox, server_opts, #{}),
    ListenOpts = application:get_env(grpcbox, listen_opts, #{}),
    PoolOpts = application:get_env(grpcbox, pool_opts, #{}),
    TransportOpts = application:get_env(grpcbox, transport_opts, #{}),
    grpcbox_services_simple_sup:start_child(#{server_opts => ServerOpts,
                                              grpc_opts => GrpcOpts,
                                              listen_opts => ListenOpts,
                                              pool_opts => PoolOpts,
                                              transport_opts => TransportOpts}).

start_server(Opts) ->
    grpcbox_services_simple_sup:start_child(Opts).

