-module(grpcbox_utils).

-export([headers_to_metadata/1,
         maybe_decode_header/2,
         decode_header/1,
         encode_headers/1,
         is_reserved_header/1,
         status_to_string/1]).

-include("grpcbox.hrl").

headers_to_metadata(H) ->
    lists:foldl(fun({K, V}, Acc) ->
                        case is_reserved_header(K) of
                            true ->
                                Acc;
                            false ->
                                maps:put(K, maybe_decode_header(K, V), Acc)
                        end
                end, #{}, H).

%% TODO: consolidate with grpc_lib. But have to update their header map to support
%% a list of values for a key.

maybe_decode_header(Key, Value) ->
    case binary:longest_common_suffix([Key, <<"-bin">>]) == 4 of
        true ->
            decode_header(Value);
        false ->
            Value
    end.

%% golang gRPC implementation does not add the padding that the Erlang
%% decoder needs...
decode_header(Base64) when byte_size(Base64) rem 4 == 3 ->
    base64:decode(<<Base64/bytes, "=">>);
decode_header(Base64) when byte_size(Base64) rem 4 == 2 ->
    base64:decode(<<Base64/bytes, "==">>);
decode_header(Base64) ->
    base64:decode(Base64).

encode_headers([]) ->
    [];
encode_headers([{Key, Value} | Rest]) ->
     case binary:longest_common_suffix([Key, <<"-bin">>]) == 4 of
         true ->
             [{Key, base64:encode(Value)} | encode_headers(Rest)];
         false ->
             [{Key, Value} | encode_headers(Rest)]
     end.

is_reserved_header(<<"content-type">>) -> true;
is_reserved_header(<<"grpc-message-type">>) -> true;
is_reserved_header(<<"grpc-encoding">>) -> true;
is_reserved_header(<<"grpc-message">>) -> true;
is_reserved_header(<<"grpc-status">>) -> true;
is_reserved_header(<<"grpc-timeout">>) -> true;
is_reserved_header(<<"grpc-status-details-bin">>) -> true;
is_reserved_header(<<"te">>) -> true;
is_reserved_header(_) -> false.

-spec status_to_string(binary()) -> binary().
status_to_string(?GRPC_STATUS_OK) ->
    <<"OK">>;
status_to_string(?GRPC_STATUS_CANCELLED) ->
    <<"CANCELLED">>;
status_to_string(?GRPC_STATUS_UNKNOWN) ->
    <<"UNKNOWN">>;
status_to_string(?GRPC_STATUS_INVALID_ARGUMENT) ->
    <<"INVALID_ARGUMENT">>;
status_to_string(?GRPC_STATUS_DEADLINE_EXCEEDED) ->
    <<"DEADLINE_EXCEEDED">>;
status_to_string(?GRPC_STATUS_NOT_FOUND) ->
    <<"NOT_FOUND">>;
status_to_string(?GRPC_STATUS_ALREADY_EXISTS) ->
    <<"ALREADY_EXISTS">>;
status_to_string(?GRPC_STATUS_PERMISSION_DENIED) ->
    <<"PERMISSION_DENIED">>;
status_to_string(?GRPC_STATUS_RESOURCE_EXHAUSTED) ->
    <<"RESOURCE_EXHAUSTED">>;
status_to_string(?GRPC_STATUS_FAILED_PRECONDITION) ->
    <<"FAILED_PRECONDITION">>;
status_to_string(?GRPC_STATUS_ABORTED) ->
    <<"ABORTED">>;
status_to_string(?GRPC_STATUS_OUT_OF_RANGE) ->
    <<"OUT_OF_RANGE">>;
status_to_string(?GRPC_STATUS_UNIMPLEMENTED) ->
    <<"UNIMPLEMENTED">>;
status_to_string(?GRPC_STATUS_INTERNAL) ->
    <<"INTERNAL">>;
status_to_string(?GRPC_STATUS_UNAVAILABLE) ->
    <<"UNAVAILABLE">>;
status_to_string(?GRPC_STATUS_DATA_LOSS) ->
    <<"DATA_LOSS">>;
status_to_string(?GRPC_STATUS_UNAUTHENTICATED) ->
    <<"UNAUTHENTICATED">>;
status_to_string(Code) ->
    <<"CODE_", Code/binary>>.
