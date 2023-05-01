-module(routeguide_route_guide).

-include("grpcbox.hrl").

-export([get_feature/3,
         list_features/3,
         record_route/3,
         route_chat/3,
         generate_error/3,
         streaming_generate_error/3]).

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

-spec get_feature(Ctx :: ctx:t(), Message :: point(), term()) -> {ok, feature(), ctx:t()}.
get_feature(Ctx, Message, _) ->
    Feature = #{name => find_point(Message, data()),
                location => Message},
    {ok, Feature, Ctx}.

-spec list_features(Message::rectangle(), GrpcStream :: grpcbox_stream:t(), term()) -> ok.
list_features(_Message, GrpcStream, _) ->
    grpcbox_stream:add_headers([{<<"info">>, <<"this is a test-implementation">>}], GrpcStream),
    grpcbox_stream:send(#{name => <<"Tour Eiffel">>,
                                        location => #{latitude => 3,
                                                      longitude => 5}}, GrpcStream),
    grpcbox_stream:send(#{name => <<"Louvre">>,
                          location => #{latitude => 4,
                                        longitude => 5}}, GrpcStream),

    grpcbox_stream:add_trailers([{<<"nr_of_points_sent">>, <<"2">>}], GrpcStream),
    ok.

-spec record_route(reference(), GrpcStream :: grpcbox_stream:t(), term()) -> {ok, route_summary(), grpcbox_stream:t()}.
record_route(Ref, GrpcStream, _) ->
    record_route_loop(Ref, #{t_start => erlang:system_time(1),
                        acc => []}, GrpcStream).

record_route_loop(Ref, Data=#{t_start := T0, acc := Points}, GrpcStream) ->
    receive
        {Ref, eos} ->
            %% receiving 'eos' tells us that we need to return a result.
            {ok, #{elapsed_time => erlang:system_time(1) - T0,
                   point_count => length(Points),
                   feature_count => count_features(Points),
                   distance => distance(Points)}, GrpcStream};
        {Ref, Point} ->
            record_route_loop(Ref, Data#{acc => [Point | Points]}, GrpcStream)
    end.

-spec route_chat(reference(), GrpcStream :: grpcbox_stream:t(), term()) -> ok.
route_chat(Ref, GrpcStream, _) ->
    route_chat_loop(Ref, [], GrpcStream).

route_chat_loop(Ref, Data, GrpcStream) ->
    receive
        {Ref, eos} ->
            ok;
        {Ref, #{location := Location} = P} ->
            Messages = proplists:get_all_values(Location, Data),
            [grpcbox_stream:send(Message, GrpcStream) || Message <- Messages],
            route_chat_loop(Ref, [{Location, P} | Data], GrpcStream)
    end.

<<<<<<< HEAD
-spec generate_error(Ctx :: ctx:ctx(), Message :: map(), term()) -> grpcbox_stream:grpc_extended_error_response().
generate_error(_Ctx, _Message, _) ->
=======
-spec generate_error(Ctx :: ctx:t(), Message :: map()) -> grpcbox_stream:grpc_extended_error_response().
generate_error(_Ctx, _Message) ->
>>>>>>> a5aa6e918a2ddbff40e8ebb3c12b1453fe953e03
    {
        grpc_extended_error, #{
            status => ?GRPC_STATUS_INTERNAL,
            message => <<"error_message">>,
            trailers => #{
                <<"generate_error_trailer">> => <<"error_trailer">>
            }
        }
    }.

-spec streaming_generate_error(Message :: map(), GrpcStream :: grpcbox_stream:t(), term()) -> no_return().
streaming_generate_error(_Message, _GrpcStream, _) ->
    exit(
        {
            grpc_extended_error, #{
                status => ?GRPC_STATUS_INTERNAL,
                message => <<"error_message">>,
                trailers => #{
                    <<"generate_error_trailer">> => <<"error_trailer">>
                }
            }
        }
    ).

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
