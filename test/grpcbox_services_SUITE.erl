%% A service registered as {Module, AdditionalArgs}: the args reach every
%% method's handler, without a copy per method in the services table or per
%% stream in the process serving it.
-module(grpcbox_services_SUITE).

-export([all/0,
         init_per_suite/1,
         end_per_suite/1,
         additional_args_reach_the_handler/1,
         services_table_holds_additional_args_at_most_once/1,
         stream_does_not_copy_additional_args/1]).

-include_lib("stdlib/include/assert.hrl").

-define(PORT, 8095).
-define(LISTEN_OPTS, #{ip => {127, 0, 0, 1}, port => ?PORT}).

all() ->
    [additional_args_reach_the_handler,
     services_table_holds_additional_args_at_most_once,
     stream_does_not_copy_additional_args].

init_per_suite(Config) ->
    ok = application:load(grpcbox),
    application:set_env(grpcbox, servers, []),
    application:set_env(grpcbox, client, #{channels => [{default_channel, [{http, "127.0.0.1", ?PORT, []}], #{}}]}),
    {ok, _} = application:ensure_all_started(grpcbox),
    {ok, _} = grpcbox:start_server(#{grpc_opts => #{service_protos => [route_guide_pb],
                                                    services => #{'routeguide.RouteGuide' =>
                                                                      {args_route_guide, args()}}},
                                     listen_opts => ?LISTEN_OPTS}),
    ok = wait_for_channel(default_channel, 50),
    Config.

end_per_suite(_Config) ->
    application:stop(grpcbox),
    ok.

additional_args_reach_the_handler(_Config) ->
    #{name := Name} = get_feature(),
    ?assertEqual(<<"from additional args">>, Name).

services_table_holds_additional_args_at_most_once(_Config) ->
    Table = grpcbox_services_sup:services_sup_name(?LISTEN_OPTS),
    ?assert(ets:info(Table, size) > 1),
    ?assert(ets:info(Table, memory) < args_words()).

stream_does_not_copy_additional_args(_Config) ->
    #{location := #{latitude := HandlerHeapWords}} = get_feature(),
    ?assert(HandlerHeapWords < args_words()).

wait_for_channel(_Channel, 0) ->
    {error, channel_not_ready};
wait_for_channel(Channel, Tries) ->
    case catch grpcbox_channel:is_ready(Channel) of
        true -> ok;
        _ -> timer:sleep(100), wait_for_channel(Channel, Tries - 1)
    end.

get_feature() ->
    {ok, Feature, _} = routeguide_route_guide_client:get_feature(#{latitude => 1, longitude => 2}),
    Feature.

%% Big enough that a copy of it dwarfs everything else in the table or a
%% stream's heap.
args() ->
    #{name => <<"from additional args">>, padding => lists:seq(1, 20000)}.

args_words() ->
    erts_debug:flat_size(args()).
