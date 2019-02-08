%%%-------------------------------------------------------------------
%% @doc grpc client
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox).

-export([start_server/1,
         server_child_spec/5]).

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

-spec start_server(server_opts()) -> supervisor:startchild_ret().
start_server(Opts) ->
    grpcbox_services_simple_sup:start_child(Opts).

server_child_spec(ServerOpts, GrpcOpts, ListenOpts, PoolOpts, TransportOpts) ->
    #{id => grpcbox_services_sup,
      start => {grpcbox_services_sup, start_link, [ServerOpts, GrpcOpts, ListenOpts,
                                                   PoolOpts, TransportOpts]},
      type => supervisor,
      restart => permanent,
      shutdown => 1000}.
