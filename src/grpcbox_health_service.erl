-module(grpcbox_health_service).

-export([check/3,
         watch/3]).

check(Ctx, #{service := <<>>}, _) ->
    {ok, #{status => 'SERVING'}, Ctx};
check(Ctx, #{service := _Service}, _) ->
    %% TODO: lookup if we are serving this service
    {ok, #{status => 'UNKNOWN'}, Ctx}.

watch(_Request, _Stream, _) ->
    ok.
