-module(grpcbox_stream).

-include_lib("chatterbox/include/http2.hrl").
-include("grpcbox.hrl").

-behaviour(h2_stream).

-export([send/2,
         send/3,
         add_headers/2,
         add_trailers/2,
         handle_streams/2,
         handle_info/2]).

-export([init/3,
         on_receive_request_headers/2,
         on_send_push_promise/2,
         on_receive_request_data/2,
         on_request_end_stream/1]).

-export_type([t/0,
              grpc_status/0,
              grpc_status_message/0,
              grpc_error/0,
              grpc_error_response/0]).

-record(state, {handler            :: pid(),
                socket,
                auth_fun,
                ctx                :: ctx:ctx(),
                req_headers=[]     :: list(),
                input_ref          :: reference(),
                callback_pid       :: pid(),
                connection_pid     :: pid(),
                request_encoding   :: gzip | undefined,
                response_encoding  :: gzip | undefined,
                content_type       :: proto | json,
                resp_headers=[]    :: list(),
                resp_trailers=[]   :: list(),
                headers_sent=false :: boolean(),
                stream_id          :: stream_id(),
                method             :: #method{}}).

-opaque t() :: #state{}.

-type grpc_status_message() :: unicode:chardata().
-type grpc_status() :: 0..16.
-type grpc_error() :: {grpc_status(), grpc_status_message()}.
-type grpc_error_response() :: {grpc_error, grpc_error()}.


-define(THROW(Status, Message), throw({grpc_error, {Status, Message}})).

init(ConnPid, StreamId, [Socket, AuthFun]) ->
    process_flag(trap_exit, true),
    {ok, #state{connection_pid=ConnPid,
                stream_id=StreamId,
                auth_fun=AuthFun,
                socket=Socket,
                handler=self()}}.

on_receive_request_headers(Headers, State=#state{auth_fun=AuthFun,
                                                 socket=Socket}) ->
    %% proplists:get_value(<<":method">>, Headers) =:= <<"POST">>,
    case string:lexemes(proplists:get_value(<<":path">>, Headers), "/") of
        [Service, Method] ->
            case ets:lookup(?SERVICES_TAB, {Service, Method}) of
                [M=#method{input={_, InputStreaming}}] ->
                    RequestEncoding = parse_options(<<"grpc-encoding">>, Headers),
                    ResponseEncoding = parse_options(<<"grpc-accept-encoding">>, Headers),
                    ContentType = parse_options(<<"content-type">>, Headers),

                    Metadata =  lists:foldl(fun({K = <<"grpc-", _/binary>>, V}, Acc) ->
                                                    maps:put(K, V, Acc);
                                               (_, Acc) ->
                                                    Acc
                                            end, #{}, Headers),
                    Ctx = case parse_options(<<"grpc-timeout">>, Headers) of
                              infinity ->
                                  ctx:with_values(Metadata);
                              D ->
                                  ctx:with_deadline(ctx:with_values(Metadata), D, nanosecond)
                          end,
                    RespHeaders = [{<<":status">>, <<"200">>},
                                   {<<"user-agent">>, <<"grpc-erlang/0.1.0">>},
                                   {<<"content-type">>, content_type(ContentType)}
                                   | response_encoding(ResponseEncoding)],

                    State1 = State#state{resp_headers=RespHeaders,
                                         req_headers=Headers,
                                         request_encoding=RequestEncoding,
                                         response_encoding=ResponseEncoding,
                                         content_type=ContentType,
                                         ctx=Ctx,
                                         method=M},
                    case authenticate(sock:peercert(Socket), AuthFun) of
                        {true, _Identity} ->
                            case InputStreaming of
                                true ->
                                    Ref = make_ref(),
                                    Pid = proc_lib:spawn_link(?MODULE, handle_streams,
                                                              [Ref, State1#state{handler=self()}]),
                                    {ok, State1#state{input_ref=Ref,
                                                      callback_pid=Pid}};
                                _ ->
                                    {ok, State1}
                            end;
                        _ ->
                            end_stream(?GRPC_STATUS_UNAUTHENTICATED, <<"">>, State1)
                    end;
                _ ->
                    end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"Method not found on server">>, State)
            end;
        _ ->
            end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"failed parsing path">>, State#state{resp_headers=[{<<":status">>, <<"200">>},
                                                                                                        {<<"user-agent">>, <<"grpc-erlang/0.1.0">>}]}),
            {ok, State#state{resp_headers=[{<<":status">>, <<"200">>},
                                   {<<"user-agent">>, <<"grpc-erlang/0.1.0">>}]}}
    end.

authenticate(_, undefined) ->
    {true, undefined};
authenticate({ok, Cert}, Fun) ->
    Fun(Cert);
authenticate(_, _) ->
    false.

handle_streams(Ref, State=#state{method=#method{module=Module,
                                                function=Function,
                                                output={_, false}}}) ->
    {ok, Response, State1} = Module:Function(Ref, State),
    send(false, Response, State1);
handle_streams(Ref, State=#state{method=#method{module=Module,
                                                function=Function,
                                                output={_, true}}}) ->
    Module:Function(Ref, State).

on_send_push_promise(_, State) ->
    {ok, State}.

on_receive_request_data(Bin, State=#state{request_encoding=Encoding,
                                          input_ref=Ref,
                                          callback_pid=Pid,
                                          ctx=Ctx,
                                          method=#method{module=Module,
                                                         function=Function,
                                                         proto=Proto,
                                                         input={Input, InputStream},
                                                         output={_Output, OutputStream}}})->
    try
        Messages = split_frame(Bin, Encoding),
        State1 = lists:foldl(fun(EncodedMessage, StateAcc) ->
                                     try Proto:decode_msg(EncodedMessage, Input) of
                                         Message ->
                                             case {InputStream, OutputStream} of
                                                 {true, _} ->
                                                     Pid ! {Ref, Message},
                                                     StateAcc;
                                                 {false, true} ->
                                                     _ = proc_lib:spawn_link(?MODULE, handle_streams,
                                                                             [Message, StateAcc#state{handler=self()}]),
                                                     StateAcc;
                                                 {false, false} ->
                                                     {ok, Response, Ctx1} = Module:Function(Ctx, Message),
                                                     send(false, Response, StateAcc#state{ctx=Ctx1})
                                             end
                                     catch
                                         error:{gpb_error, _} ->
                                             ?THROW(?GRPC_STATUS_INTERNAL, <<"Error parsing request protocol buffer">>)
                                     end
                             end, State, Messages),
        {ok, State1}
    catch
        throw:{grpc_error, {Status, Message}} ->
            end_stream(Status, Message, State);
        _C:_T ->
            end_stream(?GRPC_STATUS_UNKNOWN, <<>>, State)
    end.

on_request_end_stream(State=#state{input_ref=Ref,
                                   callback_pid=Pid,
                                   method=#method{input={_Input, true},
                                                  output={_Output, false}}}) ->
    Pid ! {Ref, eos},
    {ok, State};
on_request_end_stream(State=#state{input_ref=Ref,
                                   callback_pid=Pid,
                                   method=#method{input={_Input, true},
                                                  output={_Output, true}}}) ->
    Pid ! {Ref, eos},
    {ok, State};
on_request_end_stream(State=#state{input_ref=_Ref,
                                   callback_pid=_Pid,
                                   method=#method{input={_Input, false},
                                                  output={_Output, true}}}) ->
    {ok, State};
on_request_end_stream(State=#state{method=#method{output={_Output, false}}}) ->
    end_stream(State),
    {ok, State};
on_request_end_stream(State) ->
    end_stream(State),
    {ok, State}.

%% Internal

end_stream(State) ->
    end_stream(?GRPC_STATUS_OK, <<>>, State).

end_stream(Status, Message, State=#state{headers_sent=false}) ->
    end_stream(Status, Message, send_headers(State));
end_stream(Status, Message, #state{connection_pid=ConnPid,
                                   stream_id=StreamId,
                                   resp_trailers=Trailers}) ->
    h2_connection:send_trailers(ConnPid, StreamId, [{<<"grpc-status">>, Status},
                                                    {<<"grpc-message">>, Message} | Trailers],
                                [{send_end_stream, true}]).

send_headers(State=#state{headers_sent=true}) ->
    State;
send_headers(State=#state{connection_pid=ConnPid,
                          stream_id=StreamId,
                          resp_headers=Headers,
                          headers_sent=false}) ->
    h2_connection:send_headers(ConnPid, StreamId, Headers, [{send_end_stream, false}]),
    State#state{headers_sent=true}.


handle_info({add_headers, Headers}, State) ->
    update_headers(Headers, State);
handle_info({add_trailers, Trailers}, State) ->
    update_trailers(Trailers, State);
handle_info({send_proto, Message}, State) ->
    send(false, Message, State);
handle_info({'EXIT', _, _}, State) ->
    end_stream(State),
    State.

add_headers(Headers, #state{handler=Pid}) ->
    Pid ! {add_headers, Headers}.

add_trailers(Headers, #state{handler=Pid}) ->
    Pid ! {add_trailers, Headers}.

update_headers(Headers, State=#state{resp_headers=RespHeaders}) ->
    State#state{resp_headers=RespHeaders++Headers}.

update_trailers(Trailers, State=#state{resp_trailers=RespTrailers}) ->
    State#state{resp_trailers=RespTrailers++Trailers}.

send(Message, #state{handler=Pid}) ->
    Pid ! {send_proto, Message}.

send(End, Message, State=#state{headers_sent=false}) ->
    State1 = send_headers(State),
    send(End, Message, State1);
send(End, Message, State=#state{connection_pid=ConnPid,
                                stream_id=StreamId,
                                response_encoding=Encoding,
                                method=#method{proto=Proto,
                                               input={_Input, _},
                                               output={Output, _}}}) ->
    BodyToSend = Proto:encode_msg(Message, Output),
    OutFrame = encode_frame(Encoding, BodyToSend),
    ok = h2_connection:send_body(ConnPid, StreamId, OutFrame, [{send_end_stream, End}]),
    State.

encode_frame(gzip, Bin) ->
    CompressedBin = zlib:gzip(Bin),
    Length = byte_size(CompressedBin),
    <<1, Length:32, CompressedBin/binary>>;
encode_frame(_, Bin) ->
    Length = byte_size(Bin),
    <<0, Length:32, Bin/binary>>.

split_frame(Frame, Encoding) ->
    split_frame(Frame, Encoding, []).

split_frame(<<>>, _Encoding, Acc) ->
    lists:reverse(Acc);
split_frame(<<0, Length:32, Encoded:Length/binary, Rest/binary>>, Encoding, Acc) ->
    split_frame(Rest, Encoding, [Encoded | Acc]);
split_frame(<<1, Length:32, Compressed:Length/binary, Rest/binary>>, Encoding, Acc) ->
    Encoded = case Encoding of
                  <<"gzip">> ->
                      try zlib:gunzip(Compressed)
                      catch
                          error:data_error ->
                              ?THROW(?GRPC_STATUS_INTERNAL,
                                     <<"Could not decompress but compression algorithm supported">>)
                      end;
                  _ ->
                      ?THROW(?GRPC_STATUS_UNIMPLEMENTED,
                             <<"Compression mechanism used by client not supported by the server">>)
              end,
    split_frame(Rest, Encoding, [Encoded | Acc]).

response_encoding(gzip) ->
    [{<<"grpc-encoding">>, <<"gzip">>}];
response_encoding(snappy) ->
    [{<<"grpc-encoding">>, <<"snappy">>}];
response_encoding(deflate) ->
    [{<<"grpc-encoding">>, <<"deflate">>}];
response_encoding(undefined) ->
    [].

content_type(json) ->
    <<"application/grpc+json">>;
content_type(_) ->
    <<"application/grpc+proto">>.

timeout_to_duration(T, "H") ->
    erlang:convert_time_unit(timer:hours(T), millisecond, nanosecond);
timeout_to_duration(T, "M") ->
    erlang:convert_time_unit(timer:minutes(T), millisecond, nanosecond);
timeout_to_duration(T, "S") ->
    erlang:convert_time_unit(T, second, nanosecond);
timeout_to_duration(T, "m") ->
    erlang:convert_time_unit(T, millisecond, nanosecond);
timeout_to_duration(T, "u") ->
    erlang:convert_time_unit(T, microsecond, nanosecond);
timeout_to_duration(T, "n") ->
    timer:seconds(T).


parse_options(<<"grpc-timeout">>, Headers) ->
    case proplists:get_value(<<"grpc-timeout">>, Headers, infinity) of
        infinity ->
            infinity;
        T ->
            {I, U} = string:to_integer(T),
            timeout_to_duration(I, U)
    end;
parse_options(<<"content-type">>, Headers) ->
    case proplists:get_value(<<"content-type">>, Headers, undefined) of
        undefined ->
            proto;
        <<"application/grpc">> ->
            proto;
        <<"application/grpc+proto">> ->
            proto;
        <<"application/grpc+json">> ->
            json;
        <<"application/grpc+", _>> ->
            ?THROW(?GRPC_STATUS_UNIMPLEMENTED, <<"unknown content-type">>)
    end;
parse_options(<<"grpc-encoding">>, Headers) ->
    parse_encoding(<<"grpc-encoding">>, Headers);
parse_options(<<"grpc-accept-encoding">>, Headers) ->
    parse_encoding(<<"grpc-accept-encoding">>, Headers).

parse_encoding(EncodingType, Headers) ->
    case proplists:get_value(EncodingType, Headers, undefined) of
        undefined ->
            undefined;
        <<"gzip">> ->
            gzip;
        <<"snappy">> ->
            snappy;
        <<"deflate">> ->
            deflate;
        _ ->
            ?THROW(?GRPC_STATUS_UNIMPLEMENTED, <<"unknown encoding">>)
    end.
