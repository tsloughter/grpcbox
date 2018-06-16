-module(grpcbox_metadata).

-export([new/1,
         new_incoming_ctx/1,
         append_to_outgoing_ctx/2,
         pairs/1,
         join/1,
         from_incoming_ctx/1,
         from_outgoing_ctx/1]).

-export_type([t/0,
              key/0,
              value/0]).

-type key() :: unicode:chardata(). %% but only ASCII allowed?
-type value() :: unicode:chardata().

-type t() :: #{key() => value()}.

%% New creates an MD from a given key-value map.
%%
%% Only the following ASCII characters are allowed in keys:
%%  - digits: 0-9
%%  - uppercase letters: A-Z (normalized to lower)
%%  - lowercase letters: a-z
%%  - special characters: -_.
%% Uppercase letters are automatically converted to lowercase.
%%
%% Keys beginning with "grpc-" are reserved for grpc-internal use only and may
%% result in errors if set in metadata.
-spec new(#{unicode:chardata() => unicode:chardata()}) -> t().
new(Map) ->
    maps:fold(fun(K, V, Acc) ->
                  maps:put(string:lowercase(K), V, Acc)
              end, #{}, Map).

new_incoming_ctx(Map) ->
    ctx:with_value(md_incoming_key, new(Map)).

append_to_outgoing_ctx(Ctx, Map) ->
    ctx:with_value(md_outgoing_key, join([from_outgoing_ctx(Ctx), new(Map)])).

-spec pairs([{key(), value()}]) -> t().
pairs(List) ->
    lists:foldl(fun({Key, Value}, Map) ->
                        update(Key, Value, Map)
                end, #{}, List).

-spec join([t()]) -> t().
join(Metadatas) ->
    lists:foldl(fun(Map, Acc) ->
                    maps:fold(fun(Key, Value, Acc1) ->
                                  update(Key, Value, Acc1)
                              end, Acc, Map)
                end, #{}, Metadatas).

-spec from_incoming_ctx(ctx:t()) -> t().
from_incoming_ctx(Ctx) ->
    ctx:get(Ctx, md_incoming_key, #{}).

-spec from_outgoing_ctx(ctx:t()) -> t().
from_outgoing_ctx(Ctx) ->
    ctx:get(Ctx, md_outgoing_key, #{}).

%% internal

update(Key, Value, Map) ->
    maps:update_with(Key, fun(V) when is_list(V) ->
                                  [Value | V ];
                             (V) ->
                                  [Value, V]
                          end, Value, Map).
