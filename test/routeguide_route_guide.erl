-module(routeguide_route_guide).

-include("grpcbox.hrl").

-export([
         init/2,
         get_feature/2,
         list_features/2,
         record_route/2,
         route_chat/2,
         generate_error/2,
         streaming_generate_error/2]).

-type route_summary() ::
    #{point_count => integer(),
      feature_count => integer(),
      distance => integer(),
      elapsed_time => integer()}.

-type point() ::
    #{latitude => integer(),
      longitude => integer()}.

-type rectangle() ::
    #{lo => point(),
      hi => point()}.

-type route_note() ::
    #{location => point(),
      message => string()}.

-type feature() ::
    #{name => string(),
      location => point()}.

%% define init functions required for each RPC, if required
init(_RPC=record_route, GrpcStream)->
    grpcbox_stream:stream_handler_state(
        GrpcStream,
        #{t_start => erlang:system_time(1), acc => []}
    );
init(_RPC=route_chat, GrpcStream)->
    grpcbox_stream:stream_handler_state(
        GrpcStream,
        []
    );
init(_RPC=closed_stream, GrpcStream)->
    grpcbox_stream:stream_handler_state(
        GrpcStream,
        #{t_start => erlang:system_time(1), acc => []}
    );
init(_RPC, GrpcStream)->
    GrpcStream.

-spec get_feature(Ctx :: ctx:ctx(), Message :: point()) -> {ok, feature(), ctx:ctx()}.
get_feature(Ctx, Message) ->
    Feature = #{name => find_point(Message, data()),
                location => Message},
    {ok, Feature, Ctx}.

-spec list_features(Message::rectangle(), GrpcStream :: grpcbox_stream:t()) -> ok.
list_features(_Message, GrpcStream) ->
    GrpcStream0 = grpcbox_stream:update_headers([{<<"info">>, <<"this is a test-implementation">>}], GrpcStream),
    GrpcStream1 = grpcbox_stream:send(false, #{name => <<"Tour Eiffel">>,
                                        location => #{latitude => 3,
                                                      longitude => 5}}, GrpcStream0),
    GrpcStream2 = grpcbox_stream:send(false, #{name => <<"Louvre">>,
                          location => #{latitude => 4,
                                        longitude => 5}}, GrpcStream1),
    GrpcStream3 = grpcbox_stream:update_trailers([{<<"nr_of_points_sent">>, <<"2">>}], GrpcStream2),
    {stop, GrpcStream3}.

-spec record_route(ReqMessage :: any(), GrpcStream :: grpcbox_stream:t()) -> {stop, route_summary(), grpcbox_stream:t()} | {ok, grpcbox_stream:t()}.
record_route(ReqMessage, GrpcStream) ->
    HandlerState = grpcbox_stream:stream_handler_state(GrpcStream),
    record_route(ReqMessage, HandlerState, GrpcStream).

-spec record_route(ReqMessage :: any(), HandlerState :: any(), GrpcStream :: grpcbox_stream:t()) -> {stop, route_summary(), grpcbox_stream:t()} | {ok, grpcbox_stream:t()}.
record_route(eos, _HandlerState=#{t_start := T0, acc := Points}, GrpcStream) ->
    %% receiving 'eos' tells us that we need to return a result.
    {stop, #{elapsed_time => erlang:system_time(1) - T0,
           point_count => length(Points),
           feature_count => count_features(Points),
           distance => distance(Points)}, GrpcStream};
record_route(ReqMessage, HandlerState=#{t_start := _T0, acc := Points}, GrpcStream) ->
    NewStreamState0 = grpcbox_stream:stream_handler_state(
        GrpcStream,
        HandlerState#{acc => [ReqMessage | Points]}
    ),
    {ok, NewStreamState0}.

-spec route_chat(ReqMessage :: any(), GrpcStream :: grpcbox_stream:t()) -> {stop, grpcbox_stream:t()} | {ok, grpcbox_stream:t()}.
route_chat(ReqMessage, GrpcStream) ->
    HandlerState = grpcbox_stream:stream_handler_state(GrpcStream),
    route_chat(ReqMessage, HandlerState, GrpcStream).

-spec route_chat(ReqMessage :: any(), HandlerState :: any(), GrpcStream :: grpcbox_stream:t()) -> {stop, grpcbox_stream:t()} | {ok, grpcbox_stream:t()}.
route_chat(eos, _HandlerState, GrpcStream) ->
    {stop, GrpcStream};
route_chat(ReqMessage=#{location := Location}, HandlerState, GrpcStream) ->
    Messages = proplists:get_all_values(Location, HandlerState),
    [grpcbox_stream:send(false, Message, GrpcStream) || Message <- Messages],
    NewStreamState0 = grpcbox_stream:stream_handler_state(
        GrpcStream,
        [{Location, ReqMessage} | HandlerState]
    ),
    {ok, NewStreamState0}.

-spec generate_error(Ctx :: ctx:ctx(), Message :: map()) -> grpcbox_stream:grpc_extended_error_response().
generate_error(_Ctx, _Message) ->
    {
        grpc_extended_error, #{
            status => ?GRPC_STATUS_INTERNAL,
            message => <<"error_message">>,
            trailers => #{
                <<"generate_error_trailer">> => <<"error_trailer">>
            }
        }
    }.

-spec streaming_generate_error(Message :: map(), GrpcStream :: grpcbox_stream:t()) -> no_return().
streaming_generate_error(_Message, _GrpcStream) ->
%%    exit(
        {
            grpc_extended_error, #{
                status => ?GRPC_STATUS_INTERNAL,
                message => <<"error_message">>,
                trailers => #{
                    <<"generate_error_trailer">> => <<"error_trailer">>
                }
            }
        }.
%%    ).

%% Supporting functions

data() ->
    case file:read_file("test/grpcbox_SUITE_data/route_guide_db.json") of
        {ok, Json} ->
            jsx:decode(Json, [return_maps, {labels, atom}]);
        {error, enoent} ->
            {ok, Json} = file:read_file("../../../../test/grpcbox_SUITE_data/route_guide_db.json"),
            jsx:decode(Json, [return_maps, {labels, atom}])
    end.

find_point(_Location, []) ->
    "";
find_point(Location, [#{location := Location, name := Name} | _]) ->
    Name;
find_point(Location, [_ | T]) ->
    find_point(Location, T).

count_features(_) -> 42.
distance(_) -> 42.
