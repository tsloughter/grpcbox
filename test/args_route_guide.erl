%% A RouteGuide service whose get_feature reports what it was given as its
%% additional args (the name) and how big its own process heap is (the
%% latitude), so a test can see both that the args arrive and whether they
%% were copied into the stream process to get there.
-module(args_route_guide).

-export([get_feature/3,
         list_features/3,
         record_route/3,
         route_chat/3]).

get_feature(Ctx, _Message, #{name := Name}) ->
    {total_heap_size, HeapWords} = erlang:process_info(self(), total_heap_size),
    {ok, #{name => Name, location => #{latitude => HeapWords, longitude => 0}}, Ctx}.

list_features(_Message, _GrpcStream, _Args) ->
    ok.

record_route(_Ref, _GrpcStream, _Args) ->
    ok.

route_chat(_Ref, _GrpcStream, _Args) ->
    ok.
