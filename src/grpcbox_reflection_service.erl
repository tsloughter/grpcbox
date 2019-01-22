-module(grpcbox_reflection_service).

-export([server_reflection_info/2]).

-include("grpcbox.hrl").

-define(UNIMPLEMENTED_RESPONSE,
        {error_response,
         #{error_code => 12,
           error_message => "unimplemented method since extensions removed in proto3"}}).

server_reflection_info(Ref, Stream) ->
    receive
        {Ref, Message} ->
            handle_message(Message, Stream),
            server_reflection_info(Ref, Stream)
    end.

handle_message(#{message_request := {list_services, _}}=OriginalRequest, Stream) ->
    Services = list_services(),
    grpcbox_stream:send(#{original_request => OriginalRequest,
                          message_response => {list_services_response,
                                               #{service => Services}}}, Stream);
handle_message(#{message_request := {file_by_filename, Filename}}=OriginalRequest, Stream) ->
    Response = file_by_filename(Filename),
    grpcbox_stream:send(#{original_request => OriginalRequest,
                          message_response => Response}, Stream);
handle_message(#{message_request := {file_containing_symbol, Symbol}}=OriginalRequest, Stream) ->
    Response = file_containing_symbol(Symbol),
    grpcbox_stream:send(#{original_request => OriginalRequest,
                          message_response => Response}, Stream);

%% proto3 dropped extensions so we'll just return an empty result

handle_message(#{message_request := {all_extension_numbers_of_type, _}}=OriginalRequest, Stream) ->
    grpcbox_stream:send(#{original_request => OriginalRequest,
                          message_response => ?UNIMPLEMENTED_RESPONSE},
                        Stream);
handle_message(#{message_request := {file_containing_extension, _}}=OriginalRequest, Stream) ->
    grpcbox_stream:send(#{original_request => OriginalRequest,
                          message_response => ?UNIMPLEMENTED_RESPONSE}, Stream).

%%

list_services() ->
    ServiceSups = supervisor:which_children(grpcbox_services_simple_sup),
    lists:usort(lists:flatmap(fun services/1, ServiceSups)).

services({_, Pid, _, _}) ->
    {registered_name, Name} = erlang:process_info(Pid, registered_name),
    [#{name => Service} || Service <- ets:select(Name, [{#method{key={'$1', '_'},
                                                                 _='_'}, [], ['$1']}])].

file_by_filename(_Filename) ->
    {error_response, #{error_code => 12,
                       error_message => "not implemented yet"}}.
    %% {file_descriptor_response, #{file_descriptor_proto => [FileDescriptor]}

file_containing_symbol(Symbol) ->
    ServiceSups = supervisor:which_children(grpcbox_services_simple_sup),
    ServicePbModules = lists:usort(lists:flatmap(fun proto_modules/1, ServiceSups)),
    find(ServicePbModules, Symbol).

proto_modules({_, Pid, _, _}) ->
    {registered_name, Name} = erlang:process_info(Pid, registered_name),
    [Module || Module <- ets:select(Name, [{#method{proto='$1',
                                                    _='_'}, [], ['$1']}])].

find([], _) ->
    {error_response, #{error_code => 5,
                       error_message => "symbol not found"}};
find([M | T], Symbol) ->
    case lists:any(fun(F) -> find_symbol(M, F, Symbol) end, [service_name_to_fqbin,
                                                             fetch_enum_def]) of
        true ->
            {file_descriptor_response,
             #{file_descriptor_proto => [M:descriptor()]}};
        false ->
            find(T, Symbol)
    end.

find_symbol(M, F, Symbol) ->
    try M:F(binary_to_existing_atom(Symbol, utf8)) of
        _ ->
            true
    catch
        _:_ ->
            false
    end.
