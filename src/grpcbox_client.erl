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

-include_lib("chatterbox/include/http2.hrl").
-include("grpcbox.hrl").

-type options() :: #{channel => grpcbox_channel:t(),
                     encoding => grpcbox:encoding(),
                     atom() => any()}.

-type unary_interceptor() :: term().
-type stream_interceptor() :: term().
-type interceptor() :: unary_interceptor() | stream_interceptor().

-type stream() :: #{channel => pid(),
                    stream_id => stream_id(),
                    stream_pid => pid(),
                    monitor_ref => reference(),
                    service_def => #grpcbox_def{},
                    encoding => grpcbox:encoding()}.

-export_type([stream/0,
              options/0,
              unary_interceptor/0,
              stream_interceptor/0,
              interceptor/0]).

get_channel(Options, Type) ->
    Channel = maps:get(channel, Options, default_channel),
    Key =  maps:get(key, Options, undefined),
    PickStrategy =  maps:get(pick_strategy, Options, undefined),
    case PickStrategy of
        specify_worker -> grpcbox_channel:get(Channel, Type, Key);
        active_worker ->  grpcbox_channel:pick({Channel, active}, Type, Key);
        undefined -> grpcbox_channel:pick(Channel, Type, Key)
    end.

unary(Ctx, Service, Method, Input, Def, Options) ->
    unary(Ctx, filename:join([<<>>, Service, Method]), Input, Def, Options).

unary(Ctx, Path, Input, Def, Options) ->
    case get_channel(Options, unary) of
        {ok, {Channel, Interceptor}} ->
            Handler = fun(Ctx1, Input1) ->
                              unary_handler(Ctx1, Channel, Path, Input1, Def, Options)
                      end,

            case Interceptor of
                undefined ->
                    Handler(Ctx, Input);
                _ ->
                    Interceptor(Ctx, Channel, Handler, Path, Input, Def, Options)
            end;
        {error, _Reason}=Error ->
            Error
    end.

unary_handler(Ctx, Channel, Path, Input, Def, Options) ->
    try
        case grpcbox_client_stream:send_request(Ctx, Channel, Path, Input, Def, Options) of
            {ok, _Conn, Stream, Pid} ->
                Ref = erlang:monitor(process, Pid),
                S = #{channel => Channel,
                      stream_id => Stream,
                      stream_pid => Pid,
                      monitor_ref => Ref,
                      service_def => Def},
                case recv_end(S, grpcbox_utils:get_timeout_from_ctx(Ctx, 5000)) of
                    eos ->
                        case recv_headers(S, 0) of
                            {ok, Headers} ->
                                case recv_trailers(S) of
                                    {ok, {<<"0">>, _, Metadata}} ->
                                        case recv_data(S, 0) of
                                            {ok, Data} ->
                                                {ok, Data, #{headers => Headers,
                                                             trailers => Metadata}};
                                            stream_finished ->
                                                {ok, <<>>, #{headers => Headers,
                                                             trailers => Metadata}}
                                        end;
                                    {ok, {Status, Message, Trailers}} ->
                                        {error, {Status, Message}, #{headers => Headers,
                                                                     trailers => Trailers}};
                                    {error, _}=Error ->
                                        Error
                                end;
                            {http_error, Status, Headers} ->
                                %% different from an `error' in that it isn't from the grpc layer
                                {http_error, {Status, <<>>}, #{headers => Headers,
                                                               trailers => #{}}};
                            {error, _}=Error ->
                                Error
                        end;
                    {error, _}=Error ->
                        Error
                end;
            {error, {shutdown, econnrefused}} ->
                {error, econnrefused};
            {error, _}=Error ->
                Error
        end
    catch
        error:{badmatch, {error, {shutdown,econnrefused}}} ->
            {error, econnrefused};
        throw:{error, _}=E ->
            E
    end.

%% no input: bidrectional
stream(Ctx, Path, Def, Options) ->
    case get_channel(Options, stream) of
        {ok, {Channel, Interceptor}} ->
            case Interceptor of
                undefined ->
                    grpcbox_client_stream:new_stream(Ctx, Channel, Path, Def, Options);
                #{new_stream := NewStream} ->
                    case NewStream(Ctx, Channel, Path, Def, fun grpcbox_client_stream:new_stream/5, Options) of
                        {ok, S} ->
                            {ok, S#{stream_interceptor => Interceptor}};
                        {error, _}=Error ->
                            Error
                    end;
                _ ->
                    grpcbox_client_stream:new_stream(Ctx, Channel, Path, Def, Options)
            end;
        {error, _Reason}=Error ->
            Error
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
    case get_channel(Options, stream) of
        {ok, {Channel, _Interceptor}} ->
            case
                grpcbox_client_stream:send_request(Ctx, Channel, Path,
                                                   Input, Def, Options)
            of
                {ok, Conn, Stream, Pid} ->
                    Ref = erlang:monitor(process, Pid),
                    {ok, #{channel => Conn,
                        stream_id => Stream,
                        stream_pid => Pid,
                        monitor_ref => Ref,
                        service_def => Def}};
                {error, _Reason} = Error ->
                    Error
            end;
        {error, _Reason} = Error ->
            Error
    end.

recv_data(Stream) ->
    recv_data(Stream, 500).
recv_data(Stream=#{stream_interceptor := #{recv_msg := RecvMsg}}, Timeout) ->
    RecvMsg(Stream, fun grpcbox_client_stream:recv_msg/2, Timeout);
recv_data(Stream, Timeout) ->
    grpcbox_client_stream:recv_msg(Stream, Timeout).

recv_headers(S) ->
    recv_headers(S, 500).
recv_headers(S, Timeout) ->
    case recv(headers, S, Timeout) of
        {ok, Headers} ->
            case maps:get(<<":status">>, Headers, undefined) of
                <<"200">> ->
                    {ok, Headers};
                ErrorStatus ->
                    {http_error, ErrorStatus, Headers}
            end;
        {error, _Reason}=Error ->
            Error
    end.


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
                {trailers, Id, {Status, Message, Metadata}} ->
                    {ok, {Status, Message, Metadata}}
            after 0 ->
                    {error, unknown}
            end
    after Timeout ->
            {error, timeout}
    end.

recv_end(#{stream_id := StreamId,
            stream_pid := Pid,
            monitor_ref := Ref}, Timeout) ->
    receive
        {eos, StreamId} ->
            erlang:demonitor(Ref, [flush]),
            receive
                {'END_STREAM', StreamId} ->
                    eos
            after Timeout -> %% actually, this Timeout will never happen because of outer receive Timeout
                {error, eos}
            end;
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

