%%%-------------------------------------------------------------------
%% @doc grpc client
%% @end
%%%-------------------------------------------------------------------

-module(grpcbox_client).

-export([unary/6,
         unary/5,
         stream/4,
         stream/5,

         send/2,
         recv_headers/1,
         recv_headers/2,
         recv_data/1,
         recv_data/2,
         recv_trailers/1,
         recv_trailers/2,

         close_and_recv/1,
         close_send/1]).

-include("grpcbox.hrl").

-type options() :: #{channel => grpcbox_channel:t(),
                     encoding => grpcbox:encoding()}.

-type unary_interceptor() :: term().
-type stream_interceptor() :: term().
-type interceptor() :: unary_interceptor() | stream_interceptor().

-export_type([options/0,
              unary_interceptor/0,
              stream_interceptor/0,
              interceptor/0]).

get_channel(Options, Type) ->
    Channel = maps:get(channel, Options, default_channel),
    grpcbox_channel:pick(Channel, Type).

unary(Ctx, Service, Method, Input, Def, Options) ->
    unary(Ctx, filename:join([<<>>, Service, Method]), Input, Def, Options).

unary(Ctx, Path, Input, Def, Options) ->
    {Channel, Interceptor} = get_channel(Options, unary),

    Handler = fun(Ctx1, Input1) ->
                      unary_handler(Ctx1, Channel, Path, Input1, Def, Options)
              end,

    case Interceptor of
        undefined ->
            Handler(Ctx, Input);
        _ ->
            Interceptor(Ctx, Channel, Handler, Path, Input, Def, Options)
    end.

unary_handler(Ctx, Channel, Path, Input, Def, Options) ->
    try
        {ok, _, Stream, Pid} = grpcbox_client_stream:send_request(Ctx, Channel, Path, Input, Def, Options),
        Ref = erlang:monitor(process, Pid),
        S = #{channel => Channel,
              stream_id => Stream,
              stream_pid => Pid,
              monitor_ref => Ref,
              service_def => Def},
        case recv_end(S, 5000) of
            eos ->
                {ok, Headers} = recv_headers(S, 0),
                case recv_trailers(S) of
                    {ok, {<<"0">>, _, Metadata}} ->
                        {ok, Data} = recv_data(S, 0),
                        {ok, Data, #{headers => Headers,
                                     trailers => Metadata}};
                    {ok, {Status, Message, _Metadata}} ->
                        {error, {Status, Message}}
                end;
            {error, _}=Error ->
                Error
        end
    catch
        throw:{error, _}=E ->
            E
    end.

%% no input: bidrectional
stream(Ctx, Path, Def, Options) ->
    {Channel, Interceptor} = get_channel(Options, stream),
    case Interceptor of
        undefined ->
            grpcbox_client_stream:new_stream(Ctx, Channel, Path, Def, Options);
        #{new_stream := NewStream} ->
            {ok, S} = NewStream(Ctx, Channel, Path, Def, fun grpcbox_client_stream:new_stream/5, Options),
            {ok, S#{stream_interceptor => Interceptor}};
        _ ->
            grpcbox_client_stream:new_stream(Ctx, Channel, Path, Def, Options)
    end.

close_and_recv(Stream) ->
    close_send(Stream),
    case recv_end(Stream, 5000) of
        eos ->
            recv_data(Stream, 0);
        {error, _}=Error ->
            Error
    end.

close_send(#{channel := Conn,
             stream_id := StreamId}) ->
    ok = h2_connection:send_body(Conn, StreamId, <<>>, [{send_end_stream, true}]).
    %% h2_connection:send_trailers(Conn, StreamId, [], [{send_end_stream, true}]).

send(Stream=#{stream_interceptor := #{send_msg := SendMsg}}, Input) ->
    SendMsg(Stream, fun grpcbox_client_stream:send_msg/2, Input);
send(Stream, Input) ->
    grpcbox_client_stream:send_msg(Stream, Input).

%% input given, stream response
stream(Ctx, Path, Input, Def, Options) ->
    {Channel, _Interceptor} = get_channel(Options, stream),
    {ok, Conn, Stream, Pid} = grpcbox_client_stream:send_request(Ctx, Channel, Path, Input, Def, Options),
    Ref = erlang:monitor(process, Pid),
    {ok, #{channel => Conn,
           stream_id => Stream,
           stream_pid => Pid,
           monitor_ref => Ref,
           service_def => Def}}.

recv_data(Stream) ->
    recv_data(Stream, 500).
recv_data(Stream=#{stream_interceptor := #{recv_msg := RecvMsg}}, Timeout) ->
    RecvMsg(Stream, fun grpcbox_client_stream:recv_msg/2, Timeout);
recv_data(Stream, Timeout) ->
    grpcbox_client_stream:recv_msg(Stream, Timeout).

recv_headers(S) ->
    recv_headers(S, 500).
recv_headers(S, Timeout) ->
    recv(headers, S, Timeout).

recv_trailers(S) ->
    recv_trailers(S, 500).
recv_trailers(S, Timeout) ->
    recv(trailers, S, Timeout).

recv(Type, #{stream_id := Id,
             monitor_ref := Ref,
             stream_pid := Pid}, Timeout) ->
    receive
        {Type, Id, V} ->
            {ok, V};
        {'DOWN', Ref, process, Pid, _Reason} ->
            receive
                {trailers, Id, {<<"0">>, _Message, Metadata}} ->
                    {ok, #{trailers => Metadata}};
                {trailers, Id, {Status, Message, _Metadata}} ->
                    {error, {Status, Message}}
            after 0 ->
                    {error, unknown}
            end
    after Timeout ->
            timeout
    end.

recv_end(#{stream_id := StreamId,
           stream_pid := Pid,
           monitor_ref := Ref}, Timeout) ->
    receive
        {eos, StreamId} ->
            erlang:demonitor(Ref, [flush]),
            eos;
        {'DOWN', Ref, process, Pid, normal} ->
            %% this is sent by h2_connection after the stream process has ended
            receive
                {'END_STREAM', StreamId} ->
                    eos
            after Timeout ->
                    {error, {stream_down, normal}}
            end;
        {'DOWN', Ref, process, Pid, Reason} ->
            {error, {stream_down, Reason}}
    after Timeout ->
            {error, timeout}
    end.

