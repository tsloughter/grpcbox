%%%-------------------------------------------------------------------
%% @doc grpcbox public API
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_app).

-behaviour(application).

-export([start/2, stop/1]).

-include("grpcbox.hrl").

start(_StartType, _StartArgs) ->
    ets:new(?SERVICES_TAB, [public, named_table, set, {read_concurrency, true}, {keypos, 2}]),
    {ok, ServicePbModules} = application:get_env(grpcbox, service_protos),
    load_services(ServicePbModules),

    Options = application:get_env(grpcbox, options, []),
    AuthFun = get_authfun(application:get_env(chatterbox, ssl, false), Options),
    application:set_env(chatterbox, stream_callback_opts, [AuthFun]),
    chatterbox_sup:start_link(),

    grpcbox_sup:start_link().

get_authfun(true, Options) ->
    case proplists:get_value(auth_fun, Options) of
        undefined ->
            case proplists:get_value(client_cert_dir, Options) of
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

%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================

load_services([]) ->
    ok;
load_services([ServicePbModule | Rest]) ->
    ServiceNames = ServicePbModule:get_service_names(),
    [begin
         {{service, _}, Methods} = ServicePbModule:get_service_def(ServiceName),
         [begin
              SnakedMethodName = atom_snake_case(Name),
              SnakedServiceName = atom_snake_case(ServiceName),
              %% io:format("found: ~s/~s (~p) -> (~p)~n", [ServiceName, Name, Input, Output]),
              ets:insert(?SERVICES_TAB, #method{key={atom_to_binary(ServiceName, utf8), atom_to_binary(Name, utf8)},
                                                module=SnakedServiceName,
                                                function=SnakedMethodName,
                                                proto=ServicePbModule,
                                                input={Input, InputStream},
                                                output={Output, OutputStream},
                                                opts=Opts})
          end || #{name := Name,
                   input := Input,
                   output := Output,
                   input_stream := InputStream,
                   output_stream := OutputStream,
                   opts := Opts} <- Methods]
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
