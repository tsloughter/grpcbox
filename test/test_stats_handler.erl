-module(test_stats_handler).

-export([handle/5]).

handle(Ctx, _, rpc_begin, _, Stats) ->
    stats_pid ! {rpc_begin, erlang:monotonic_time()},
    {Ctx, Stats};
handle(Ctx, _, out_payload, #{uncompressed_size := USize,
                              compressed_size := CSize}, Stats) ->
    stats_pid ! {out_payload, USize, CSize},
    {Ctx, Stats};
handle(Ctx, _, in_payload, #{uncompressed_size := USize,
                             compressed_size := CSize}, Stats) ->
    stats_pid ! {in_payload, USize, CSize},
    {Ctx, Stats};
handle(Ctx, _, rpc_end, _, Stats) ->
    stats_pid ! {rpc_end, erlang:monotonic_time()},
    {Ctx, Stats};
handle(Ctx, _, _, _, Stats) ->
    {Ctx, Stats}.
