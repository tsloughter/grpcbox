-module(grpcbox_benchmark_client_SUITE).

-compile([export_all]).

-include_lib("eunit/include/eunit.hrl").
-include_lib("common_test/include/ct.hrl").

-include("grpcbox.hrl").

-define(COUNTER_SUM_REQS, 1).
-define(COUNTER_SUM_LATENCY, 2).

all() ->
    [{group, identity}
%     {group, gzip}
    ].

groups() ->
    Cases =
        case ct:get_config(rpc_type, unary) of
            unary -> [unary_call];
            stream -> [streaming_call]
        end,

    [{identity, Cases}
%     {gzip, Cases}
    ].

init_per_group(Encoding, Config) ->
    application:load(grpcbox),

    NrConns = lists:seq(1, ct:get_config(num_conn, 1)),
    ChannelEndpoints = [{http,
                         ct:get_config(server_addr, "localhost"),
                         ct:get_config(server_port, 8080),
                         [{nr, Nr}]} || Nr <- NrConns],
    application:set_env(grpcbox, client, #{channels => [{default_channel, ChannelEndpoints,
                                                         #{encoding => Encoding}}]}),
    {ok, _} = application:ensure_all_started(grpcbox),
    application:set_env([{chatterbox, ct:get_config(chatterbox)}]),
    Config.

end_per_group(_Encoding, _Config) ->
    application:stop(grpcbox),
    ok.

unary_call(_Config) ->
    start_calls(unary).

streaming_call(_Config) ->
    start_calls(streaming).

start_calls(CallType) ->
    log_settings(),
    NumRpc = lists:seq(1, ct:get_config(num_rpc, 1)),
    Payload = client_payload(ct:get_config(rq_size, 1)),
    SimpleRequest = #{payload => Payload, response_size => ct:get_config(rsp_size, 1)},
    CounterRefs = [counters:new(2, [atomics]) || _ <- NumRpc],
    StartTime = erlang:system_time(millisecond),
    WarmupEndTime = StartTime + (ct:get_config(warmup_dur, 10) * 1000),
    EndTime = WarmupEndTime + (ct:get_config(duration, 60) * 1000),
    ParentPid = self(),

    Pids = [spawn_link(fun() ->
                               {ok, Stream} = get_stream(CallType),
                               run_calls(Nr, Stream, SimpleRequest, lists:nth(Nr, CounterRefs), StartTime, WarmupEndTime, EndTime),
                               ParentPid ! self()
                       end) || Nr <- NumRpc],

    wait_for_processes(Pids),
    aggregate_counters(CounterRefs, WarmupEndTime, EndTime),
    ok.

wait_for_processes([]) ->
    ok;
wait_for_processes(Pids) ->
    receive
        Pid ->
            NewPids = lists:delete(Pid, Pids),
            wait_for_processes(NewPids)
    end.

get_stream(unary) ->
    {ok, undefined};
get_stream(streaming) ->
    grpc_testing_benchmark_service_client:streaming_call(ctx:new()).

run_calls(ProcNr, Stream, SimpleRequest, CounterRef, StartTime, WarmupEndTime, EndTime) ->
    CallStart = erlang:system_time(millisecond),
    case CallStart > EndTime of
        true ->
            ok;
        false ->
            run_call(Stream, SimpleRequest),
            CallEnd = erlang:system_time(millisecond),
            case CallStart >= WarmupEndTime of
                true ->
                    update_counters(CounterRef, CallEnd - CallStart);
                false ->
                    ok
            end,
            run_calls(ProcNr, Stream, SimpleRequest, CounterRef, StartTime, WarmupEndTime, EndTime)
    end.

run_call(undefined, SimpleRequest) ->
    grpc_testing_benchmark_service_client:unary_call(ctx:new(), SimpleRequest);
run_call(Stream, SimpleRequest) ->
    ok = grpcbox_client:send(Stream, SimpleRequest),
    {ok, _} = grpcbox_client:recv_data(Stream).

update_counters(CounterRef, Latency) ->
    counters:add(CounterRef, ?COUNTER_SUM_REQS, 1),
    counters:add(CounterRef, ?COUNTER_SUM_LATENCY, Latency).

log_counter(ProcNr, CounterRef, StartTime, CurrTime) ->
    Reqs = counters:get(CounterRef, ?COUNTER_SUM_REQS),
    SumLatency = counters:get(CounterRef, ?COUNTER_SUM_LATENCY),
    ct:log("ProcNr: ~p, Total reqs: ~p, Reqs/s: ~p, Avg latency: ~p", [ProcNr, Reqs, Reqs/((CurrTime-StartTime)/1000.0), SumLatency/Reqs]).

aggregate_counters(CounterRefs, StartTime, EndTime) ->
    lists:foldl(fun(CounterRef, Ix) -> log_counter(Ix, CounterRef, StartTime, EndTime), Ix+1 end, 1, CounterRefs),
    Reqs = lists:foldl(fun(CounterRef, Sum) ->
                               counters:get(CounterRef, ?COUNTER_SUM_REQS) + Sum end,
                       0,
                       CounterRefs),
    SumLatency = lists:foldl(fun(CounterRef, Sum) ->
                                     counters:get(CounterRef, ?COUNTER_SUM_LATENCY) + Sum end,
                             0,
                             CounterRefs),
    ct:log("Total reqs: ~p, Reqs/s: ~p, Avg latency: ~p", [Reqs, Reqs/((EndTime-StartTime)/1000.0), SumLatency/Reqs]),
    ct:print("Total reqs: ~p, Reqs/s: ~p, Avg latency: ~p", [Reqs, Reqs/((EndTime-StartTime)/1000.0), SumLatency/Reqs]).

client_payload(NumBytes) ->
    Body = << <<0:8>> || _ <- lists:seq(1, NumBytes)>>,
    #{type => 0,
      body => Body}.

log_settings() ->
    log_ct_parameter(server_addr),
    log_ct_parameter(server_port),
    log_ct_parameter(num_rpc),
    log_ct_parameter(num_conn),
    log_ct_parameter(warmup_dur),
    log_ct_parameter(duration),
    log_ct_parameter(rq_size),
    log_ct_parameter(rsp_size),
    log_ct_parameter(rpc_type),
    log_ct_parameter(chatterbox).

log_ct_parameter(Param) ->
    ct:log("~p: ~p" , [Param, ct:get_config(Param)]).
