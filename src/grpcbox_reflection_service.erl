-module(grpcbox_reflection_service).

-export([server_reflection_info/2]).

-include("grpcbox.hrl").

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
    FileDescriptor = file_by_filename(Filename),
    grpcbox_stream:send(#{original_request => OriginalRequest,
                          message_response => {file_descriptor_response,
                                               #{file_descriptor_proto => [FileDescriptor]}}}, Stream);
handle_message(#{message_request := {file_containing_symbol, Symbol}}=OriginalRequest, Stream) ->
    FileDescriptor = file_containing_symbol(Symbol),
    grpcbox_stream:send(#{original_request => OriginalRequest,
                          message_response => {file_descriptor_response,
                                               #{file_descriptor_proto => [FileDescriptor]}}}, Stream);

%% proto3 dropped extensions so we'll just return an empty result

handle_message(#{message_request := {all_extension_numbers_of_type, _}}=OriginalRequest, Stream) ->
    grpcbox_stream:send(#{original_request => OriginalRequest,
                          message_response => {all_extension_numbers_response, #{}}}, Stream);
handle_message(#{message_request := {file_containing_extension, _}}=OriginalRequest, Stream) ->
    grpcbox_stream:send(#{original_request => OriginalRequest,
                          message_response => {file_descriptor_response, #{}}}, Stream).

%%

list_services() ->
    ServiceSups = supervisor:which_children(grpcbox_services_simple_sup),
    lists:flatmap(fun services/1, ServiceSups).

services({_, Pid, _, _}) ->
    {registered_name, Name} = erlang:process_info(Pid, registered_name),
    [#{name => Service} || Service <- ets:select(Name, [{#method{key={'$1', '_'},
                                                                 _='_'}, [], ['$1']}])].

file_by_filename(_Filename) ->
    <<>>.

file_containing_symbol(Symbol) ->
    %% TODO: don't rely on the application env. should be a global registry
    GrpcOpts = application:get_env(grpcbox, grpc_opts, #{}),
    ServicePbModules = maps:get(service_protos, GrpcOpts),
    find(ServicePbModules, Symbol).

find([], _) ->
    <<>>;
find([M | T], Symbol) ->
    try M:fqbin_to_service_name(Symbol) of
        _ ->
            M:descriptor()
    catch
        _:_ ->
            find(T, Symbol)
    end.
