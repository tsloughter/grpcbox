-module(grpcbox_stream).

-include_lib("chatterbox/include/http2.hrl").
-include("grpcbox.hrl").

-behaviour(h2_stream).

-export([send/2,
         send/3,
         handle_streams/2,
         handle_info/2]).

-export([init/3,
         on_receive_request_headers/2,
         on_send_push_promise/2,
         on_receive_request_data/2,
         on_request_end_stream/1]).

-export_type([t/0]).

-record(state, {req_headers=[]    :: list(),
                input_ref         :: reference(),
                callback_pid      :: pid(),
                connection_pid    :: pid(),
                request_encoding  :: gzip | undefined,
                response_encoding :: gzip | undefined,
                content_type      :: proto | json,
                resp_headers      :: list(),
                stream_id         :: stream_id(),
                method            :: #method{}}).

-opaque t() :: #state{}.

-define(GRPC_STATUS_UNIMPLEMENTED, <<"12">>).

init(ConnPid, StreamId, _) ->
    {ok, #state{connection_pid=ConnPid,
                stream_id=StreamId}}.

on_receive_request_headers(Headers, State=#state{connection_pid=ConnPid,
                                                 stream_id=StreamId}) ->
    case string:lexemes(proplists:get_value(<<":path">>, Headers), "/") of
        [Service, Method] ->
            case ets:lookup(?SERVICES_TAB, {Service, Method}) of
                [M=#method{module=Module,
                           function=Function,
                           input={_, InputStreaming}}] ->
                    io:format("Calling ~p:~p~n", [Module, Function]),
                    RequestEncoding = parse_options(<<"grpc-encoding">>, Headers),
                    ResponseEncoding = parse_options(<<"grpc-accept-encoding">>, Headers),
                    ContentType = parse_options(<<"content-type">>, Headers),

                    RespHeaders = [{<<":status">>, <<"200">>},
                                   {<<"content-type">>, content_type(ContentType)}
                                   | response_encoding(ResponseEncoding)],
                    h2_connection:send_headers(ConnPid, StreamId, RespHeaders),
                    case InputStreaming of
                        true ->
                            Ref = make_ref(),
                            Pid = proc_lib:spawn_link(?MODULE, handle_streams, [Ref, State#state{resp_headers=RespHeaders,
                                                                                                 method=M}]),
                            {ok, State#state{req_headers=Headers,
                                             resp_headers=RespHeaders,
                                             input_ref=Ref,
                                             callback_pid=Pid,
                                             content_type=ContentType,
                                             request_encoding=RequestEncoding,
                                             response_encoding=ResponseEncoding,
                                             method=M}};
                        _ ->
                            {ok, State#state{req_headers=Headers,
                                             resp_headers=RespHeaders,
                                             content_type=ContentType,
                                             request_encoding=RequestEncoding,
                                             response_encoding=ResponseEncoding,
                                             method=M}}
                    end;
                _ ->
                    end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"service method not found">>, State)
            end;
        _ ->
            end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"failed parsing path">>, State)
    end.

handle_info(Info, State) ->
    io:format("HELLO INFO ~p~n", [Info]),
    State.

handle_streams(Ref, State=#state{method=#method{module=Module,
                                                function=Function,
                                                output={_, false}}}) ->
    Response = Module:Function(Ref, State),
    send(false, Response, State);
handle_streams(Ref, State=#state{method=#method{module=Module,
                                                function=Function,
                                                output={_, true}}}) ->
    Module:Function(Ref, State).

on_send_push_promise(_, State) ->
    {ok, State}.

on_receive_request_data(Bin, State=#state{request_encoding=Encoding,
                                          input_ref=Ref,
                                          callback_pid=Pid,
                                          method=#method{module=Module,
                                                         function=Function,
                                                         proto=Proto,
                                                         input={Input, InputStream},
                                                         output={_Output, OutputStream}}})->
    try
        Messages = split_frame(Bin, Encoding),
        _State1 = [begin
                      Message = Proto:decode_msg(EncodedMessage, Input),
                      case {InputStream, OutputStream} of
                          {true, _} ->
                              Pid ! {Ref, Message},
                              State;
                          {false, true} ->
                              _ = proc_lib:spawn(Module, Function, [Message, State]),
                              State;
                          {false, false} ->
                              {ok ,Response} = Module:Function(Message, State),
                              send(false, Response, State)
                      end
                  end || EncodedMessage <- Messages],
        {ok, State}
    catch
        throw:{grpc_error, {Status, Message}} ->
            end_stream(Status, Message, State)
    end.

on_request_end_stream(State=#state{input_ref=Ref,
                                   callback_pid=Pid,
                                   method=#method{input={_Input, true},
                                                  output={_Output, false}}}) ->
    Pid ! {Ref, eos},
    end_stream(State),
    {ok, State};
on_request_end_stream(State=#state{input_ref=Ref,
                                   callback_pid=Pid,
                                   method=#method{input={_Input, true},
                                                  output={_Output, true}}}) ->
    %% {Message, _, _} = Module:Function(eos, State),
    %% send(false, Message, State),
    Pid ! {Ref, eos},
    end_stream(State),
    {ok, State};
on_request_end_stream(State=#state{input_ref=_Ref,
                                   callback_pid=_Pid,
                                   method=#method{input={_Input, false},
                                                  output={_Output, true}}}) ->
    %% {Message, _, _} = Module:Function(eos, State),
    %% send(false, Message, State),
    %% Pid ! {Ref, eos},
    end_stream(State),
    {ok, State};
on_request_end_stream(State=#state{method=#method{output={_Output, false}}}) ->
    end_stream(State),
    {ok, State}.

%% Internal

end_stream(#state{connection_pid=ConnPid,
                  stream_id=StreamId}) ->
    timer:sleep(200),
    h2_connection:send_headers(ConnPid, StreamId, [{<<"grpc-status">>, <<"0">>}], [{send_end_stream, true}]).

end_stream(Status, Message, #state{connection_pid=ConnPid,
                                   stream_id=StreamId}) ->
    timer:sleep(200),
    h2_connection:send_headers(ConnPid, StreamId, [{<<"grpc-status">>, Status},
                                                   {<<"grpc-message">>, Message}], [{send_end_stream, true}]).

send(Message, State) ->
    send(false, Message, State).

send(End, Message, State=#state{connection_pid=ConnPid,
                                stream_id=StreamId,
                                response_encoding=Encoding,
                                method=#method{proto=Proto,
                                               input={_Input, _},
                                               output={Output, _}}}) ->
    BodyToSend = Proto:encode_msg(Message, Output),
    OutFrame = encode_frame(Encoding, BodyToSend),
    h2_connection:send_body(ConnPid, StreamId, OutFrame, [{send_end_stream, End}]),
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
                      zlib:gunzip(Compressed);
                  _ ->
                      throw({grpc_error, {?GRPC_STATUS_UNIMPLEMENTED,
                                          <<"compression mechanism not supported">>}})
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
            throw({grpc_error, {?GRPC_STATUS_UNIMPLEMENTED, <<"unknown content-type">>}})
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
            throw({grpc_error, {?GRPC_STATUS_UNIMPLEMENTED, <<"unknown encoding">>}})
    end.
