-module(grpcbox_utils).

-export([headers_to_metadata/1,
         maybe_decode_header/2,
         decode_header/1,
         encode_headers/1,
         is_reserved_header/1]).

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
