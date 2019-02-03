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
    %% give the services_sup a name because in the future we might want to reference it easily for
    %% debugging purposes or live configuration changes
    ServicesSupName = services_sup_name(ListenOpts),
    supervisor:start_link({local, ServicesSupName}, ?MODULE, [ServerOpts, GrpcOpts, ListenOpts,
                                                              PoolOpts, TransportOpts, ServicesSupName]).
interceptor(Type, Opts) ->
    case maps:get(Type, Opts, undefined) of
        {Module, Function} ->
            fun Module:Function/4;
        Fun when is_function(Fun, 4) ->
            Fun;
        undefined ->
            undefined
    end.

init([ServerOpts, GrpcOpts, ListenOpts, PoolOpts, TransportOpts, ServiceSupName]) ->
    Tid = ets:new(ServiceSupName, [protected, named_table, set,
                                   {read_concurrency, true}, {keypos, 2}]),
    ServicePbModules = maps:get(service_protos, GrpcOpts),
    Services = maps:get(services, GrpcOpts, #{}),
    load_services(ServicePbModules, Services, Tid),

    AuthFun = get_authfun(maps:get(ssl, TransportOpts, false), GrpcOpts),
    UnaryInterceptor = interceptor(unary_interceptor, GrpcOpts),
    StreamInterceptor = interceptor(stream_interceptor, GrpcOpts),
    StatsHandler = maps:get(stats_handler, GrpcOpts, undefined),
    ChatterboxOpts = #{stream_callback_mod => grpcbox_stream,
                       stream_callback_opts => [Tid, AuthFun, UnaryInterceptor,
                                                StreamInterceptor, StatsHandler]},

    %% unique name for pool based on the ip and port it will listen on
    Name = pool_name(ListenOpts),

    RestartStrategy = #{strategy => rest_for_one},
    Pool = #{id => grpcbox_pool,
             start => {grpcbox_pool, start_link, [Name, chatterbox:settings(server, ServerOpts),
                                                  ChatterboxOpts, TransportOpts]}},
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
    IPAddress = maps:get(ip, ListenOpts, {0, 0, 0, 0}),
    list_to_atom(Prefix ++ "_" ++ inet_parse:ntoa(IPAddress) ++ "_" ++ integer_to_list(Port)).

get_authfun(true, Options) ->
    case maps:get(auth_fun, Options, undefined) of
        undefined ->
            case maps:get(client_cert_dir, Options, undefined) of
                undefined ->
                    undefined;
                Dir ->
                    auth_fun(Dir)
            end;
        Fun ->
            Fun
    end;
get_authfun(_, _) ->
    undefined.

-spec auth_fun(Directory::string()) -> fun(((public_key:der_encoded())) -> {true, string()} | false).
auth_fun(Directory) ->
    Ids = issuer_ids_from_directory(Directory),
    fun(Cert) ->
            {ok, IssuerID} = public_key:pkix_issuer_id(Cert, self),
            case maps:find(IssuerID, Ids) of
                {ok, Identity} ->
                    {true, Identity};
                error ->
                    false
            end
    end.

issuer_ids_from_directory(Dir) ->
    {ok, Filenames} = file:list_dir(Dir),
    Keyfiles = lists:filter(fun(N) ->
                                case filename:extension(N) of
                                    ".pem" -> true;
                                    ".crt" -> true;
                                    _ -> false
                                end
                            end, Filenames),
    maps:from_list([issuer_id_from_file(filename:join([Dir, F]))
                    || F <- Keyfiles]).

issuer_id_from_file(Filename) ->
    {certfile_to_issuer_id(Filename),
     filename:rootname(filename:basename(Filename))}.

certfile_to_issuer_id(Filename) ->
    {ok, Data} = file:read_file(Filename),
    [{'Certificate', Cert, not_encrypted}] = public_key:pem_decode(Data),
    {ok, IssuerID} = public_key:pkix_issuer_id(Cert, self),
IssuerID.

%% grpc requests are of the form `<pkg>.<Service>/<Method>` in camelcase. For this reason we
%% have gpb keep the service definitions in their original form and convert to snake case here
%% to know what module:function to call for each.
load_services([], _, _) ->
    ok;
load_services([ServicePbModule | Rest], Services, ServicesTable) ->
    ServiceNames = ServicePbModule:get_service_names(),
    [begin
         {{service, _}, Methods} = ServicePbModule:get_service_def(ServiceName),
         %% throws exception if ServiceName isn't in the map or doesn't exist
         try ServiceModule = maps:get(ServiceName, Services),
              {ServiceModule, ServiceModule:module_info(exports)} of
             {ServiceModule1, Exports} ->
                 [begin
                      SnakedMethodName = atom_snake_case(Name),
                      case lists:member({SnakedMethodName, 2}, Exports) of
                          true ->
                              ets:insert(ServicesTable, #method{key={atom_to_binary(ServiceName, utf8),
                                                                     atom_to_binary(Name, utf8)},
                                                                module=ServiceModule1,
                                                                function=SnakedMethodName,
                                                                proto=ServicePbModule,
                                                                input={Input, InputStream},
                                                                output={Output, OutputStream},
                                                                opts=Opts});
                          false ->
                              %% TODO: error? log? insert into ets as unimplemented?
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
                 %% TODO: error? log? insert into ets as unimplemented?
                 unimplemented_service
         end
     end || ServiceName <- ServiceNames],

    load_services(Rest, Services, ServicesTable).

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
