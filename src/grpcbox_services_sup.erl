%%%-------------------------------------------------------------------
%% @doc grpcbox supervisor for set of services on a port.
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_services_sup).

-behaviour(supervisor).

-export([start_link/5,
         services_sup_name/1,
         pool_name/1,
         name/2]).
-export([init/1]).

-include("grpcbox.hrl").

start_link(ServerOpts, GrpcOpts, ListenOpts, PoolOpts, TransportOpts) ->
    ServicePbModules = maps:get(service_protos, GrpcOpts),
    load_services(ServicePbModules),

    %% give the services_sup a name because in the future we might want to reference it easily for
    %% debugging purposes or live configuration changes
    Name = services_sup_name(ListenOpts),
    supervisor:start_link({local, Name}, ?MODULE, [ServerOpts, GrpcOpts, ListenOpts, PoolOpts, TransportOpts]).

init([ServerOpts, GrpcOpts, ListenOpts, PoolOpts, TransportOpts]) ->
    AuthFun = get_authfun(maps:get(ssl, ListenOpts, false), GrpcOpts),
    ChatterboxOpts = #{stream_callback_mod => grpcbox_stream,
                       stream_callback_opts => [AuthFun]},

    %% unique name for pool based on the ip and port it will listen on
    Name = pool_name(ListenOpts),

    RestartStrategy = #{strategy => rest_for_one},
    Pool = #{id => grpcbox_pool,
             start => {grpcbox_pool, start_link, [Name, chatterbox:settings(server, ServerOpts), ChatterboxOpts, TransportOpts]}},
    Socket = #{id => grpcbox_socket,
               start => {grpcbox_socket, start_link, [Name, ListenOpts, PoolOpts]}},
    {ok, {RestartStrategy, [Pool, Socket]}}.

%%

services_sup_name(ListenOpts) ->
    name("grpcbox_services_sup", ListenOpts).

pool_name(ListenOpts) ->
    name("grpcbox_pool", ListenOpts).

name(Prefix, ListenOpts) ->
    Port = maps:get(port, ListenOpts, 8080),
    IPAddress = maps:get(ip, ListenOpts, {0,0,0,0}),
    list_to_atom(Prefix ++ "_" ++ inet_parse:ntoa(IPAddress) ++ "_" ++ integer_to_list(Port)).

get_authfun(true, Options) ->
    case maps:get(auth_fun, Options, undefined) of
        undefined ->
            case maps:get(client_cert_dir, Options, undefined) of
                undefined ->
                    undefined;
                Dir ->
                    grpc_lib:auth_fun(Dir)
            end;
        Fun ->
            Fun
    end;
get_authfun(_, _) ->
    undefined.

load_services([]) ->
    ok;
load_services([ServicePbModule | Rest]) ->
    ServiceNames = ServicePbModule:get_service_names(),
    [begin
         {{service, _}, Methods} = ServicePbModule:get_service_def(ServiceName),
         SnakedServiceName = atom_snake_case(ServiceName),
         try lists:keyfind(exports, 1, SnakedServiceName:module_info()) of
             {exports, Exports} ->
                 [begin
                      SnakedMethodName = atom_snake_case(Name),
                      case lists:member({SnakedMethodName, 2}, Exports) of
                          true ->
                              %% ct:pal("found: ~s/~s (~p) -> (~p)~n", [ServiceName, Name, Input, Output]),
                              ets:insert(?SERVICES_TAB, #method{key={atom_to_binary(ServiceName, utf8),
                                                                     atom_to_binary(Name, utf8)},
                                                                module=SnakedServiceName,
                                                                function=SnakedMethodName,
                                                                proto=ServicePbModule,
                                                                input={Input, InputStream},
                                                                output={Output, OutputStream},
                                                                opts=Opts});
                          false ->
                              unimplemented_method
                      end
                  end || #{name := Name,
                           input := Input,
                           output := Output,
                           input_stream := InputStream,
                           output_stream := OutputStream,
                           opts := Opts} <- Methods]
         catch
             _:_ ->
                 unimplemented_service
         end
     end || ServiceName <- ServiceNames],

    load_services(Rest).

atom_snake_case(Name) ->
    NameString = atom_to_list(Name),
    Snaked = lists:foldl(fun(RE, Snaking) ->
                                 re:replace(Snaking, RE, "\\1_\\2", [{return, list},
                                                                     global])
                         end, NameString, [%% uppercase followed by lowercase
                                           "(.)([A-Z][a-z]+)",
                                           %% any consecutive digits
                                           "(.)([0-9]+)",
                                           %% uppercase with lowercase
                                           %% or digit before it
                                           "([a-z0-9])([A-Z])"]),
    Snaked1 = string:replace(Snaked, ".", "_", all),
    Snaked2 = string:replace(Snaked1, "__", "_", all),
    list_to_atom(string:to_lower(unicode:characters_to_list(Snaked2))).
