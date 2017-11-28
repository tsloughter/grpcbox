-module(routeguide_route_guide).

-export([get_feature/3,
         list_features/3,
         record_route/3,
         route_chat/3]).

-type 'RouteSummary'() ::
    #{point_count => integer(),
      feature_count => integer(),
      distance => integer(),
      elapsed_time => integer()}.

-type 'Point'() ::
    #{latitude => integer(),
      longitude => integer()}.

-type 'Rectangle'() ::
    #{lo => 'Point'(),
      hi => 'Point'()}.

-type 'RouteNote'() ::
    #{location => 'Point'(),
      message => string()}.

-type 'Feature'() ::
    #{name => string(),
      location => 'Point'()}.

%% RPCs for service 'RouteGuide'

-spec get_feature(Message::'Point'(), any(), State::any()) ->
    {'Feature'(), grpc:stream()} | grpc:error_response().
%% This implementation shows a few features:
%% - how to access metadata that was sent by the client,
%% - how to compress a response message
%% - how to send an error response.
get_feature(Message, Data, State) ->
    Feature = #{name => find_point(Message, data()),
                location => Message},
    %% case grpc:metadata(Stream) of
    %%     #{<<"password">> := <<"secret">>} ->
    %%         {Feature, Stream};
    %%     #{<<"password">> := _} ->
    %%         {error, 7, <<"permission denied">>, Stream};
    %%     #{<<"compressed">> := <<"true">>} ->
    %%         %% receive a compressed message
    %%         {Feature, Stream};
    %%     #{<<"metadata-bin">> := <<1,2,3,4>>} ->
    %%         {Feature, Stream};
    %%     #{<<"metadata-bin-response">> := <<"true">>} ->
    %%         %% add a binary metadata element
    %%         Stream2 = grpc:set_headers(Stream,
    %%                                      #{<<"response-bin">> => <<1,2,3,4>>}),
    %%         {Feature, Stream2};
    %%     #{<<"compression">> := <<"true">>} ->
    %%         %% send a compressed message
    %%         {Feature, grpc:set_compression(Stream, gzip)};
    %%     _ ->
            {Feature, Data, State}.
    %% end.

-spec list_features(Message::'Rectangle'(), any(), State::any()) ->
    {['Feature'()], grpc:stream()} | grpc:error_response().
%% This adds metadata to the header and to the trailer that are sent to the client.
list_features(_Message, Data, State) ->
    grpcbox_stream:send(false, #{name => "Tour Eiffel",
                          location => #{latitude => 3,
                                        longitude => 5}}, State),
    %% Stream2 = grpc:send(grpc:set_headers(Stream,
    %%                                          #{<<"info">> => <<"this is a test-implementation">>}),
    %%                       #{name => "Louvre",
    %%                         location => #{latitude => 4,
    %%                                       longitude => 5}}),
    %% Stream3 = grpc:set_trailers(Stream2, #{<<"nr_of_points_sent">> => <<"2">>}),
    {[#{name => "Louvre",
       location => #{latitude => 4,
                     longitude => 5}}], Data, State}.

-spec record_route(Message::'Point'() | eof, any(), State::any()) ->
    {continue, gprc:stream(), any()} | {'RouteSummary'(), grpc:stream()}.
%% This is a client-to-server streaming RPC. After the client has sent the last message
%% this function will be called a final time with 'eof' as the first argument. This last
%% invocation must return the response message.
record_route(FirstPoint, undefined, State) ->
    %% The fact that State == undefined tells us that this is the
    %% first point. Set the starting state, and return 'continue' to
    %% indicate that we are not done yet.
    {continue, #{t_start => erlang:system_time(1),
                 acc => [FirstPoint]}, State};
record_route(eos, Data=#{t_start := T0, acc := Points}, State) ->
    %% receiving 'eof' tells us that we need to return a result.
    {#{elapsed_time => erlang:system_time(1) - T0,
       point_count => length(Points),
       feature_count => count_features(Points),
       distance => distance(Points)}, Data, State};
record_route(Point, #{acc := Acc} = Data, State) ->
    {continue, Data#{acc => [Point | Acc]}, State}.

-spec route_chat(Message::'RouteNote'() | eof, any(), State::any()) ->
    {['RouteNote'()], gprc:stream(), any()} | {['RouteNote'()], grpc:stream()}.
%% This is a bidirectional streaming RPC. If the client terminates the stream
%% this function will be called a final time with 'eof' as the first argument.
route_chat(In, undefined, State) ->
    route_chat(In, [], State);
route_chat(eof, Data, State) ->
    {[], Data, State};
route_chat(#{location := Location} = P, Data, State) ->
    Messages = proplists:get_all_values(Location, Data),
    {Messages, [{Location, P} | Data], State}.


%% Supporting functions

data() ->
    DataFile = "/home/tristan/Devel/grpcbox/test/grpcbox_SUITE_data/route_guide_db.json",
    {ok, Json} = file:read_file(DataFile),
    jsx:decode(Json, [return_maps, {labels, atom}]).

find_point(_Location, []) ->
    "";
find_point(Location, [#{location := Location, name := Name} | _]) ->
    Name;
find_point(Location, [_ | T]) ->
    find_point(Location, T).

count_features(_) -> 42.
distance(_) -> 42.
