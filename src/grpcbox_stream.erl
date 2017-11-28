-module(grpcbox_stream).

-include_lib("chatterbox/include/http2.hrl").
-include("grpcbox.hrl").

-behaviour(h2_stream).

-export([send/3]).

-export([init/3,
         on_receive_request_headers/2,
         on_send_push_promise/2,
         on_receive_request_data/2,
         on_request_end_stream/1]).

-record(state, {req_headers=[]    :: list(),
                connection_pid    :: pid(),
                request_encoding  :: gzip | undefined,
                response_encoding :: gzip | undefined,
                content_type      :: proto | json,
                stream_id         :: stream_id(),
                method            :: #method{},
                data              :: any()}).

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
                           function=Function}] ->
                    io:format("Calling ~p:~p~n", [Module, Function]),
                    RequestEncoding = parse_options(<<"grpc-encoding">>, Headers),
                    ResponseEncoding = parse_options(<<"grpc-accept-encoding">>, Headers),
                    ContentType = parse_options(<<"content-type">>, Headers),

                    ResponseHeaders = [{<<":status">>, <<"200">>},
                                       {<<"content-type">>, content_type(ContentType)}
                                       | response_encoding(ResponseEncoding)],
                    h2_connection:send_headers(ConnPid, StreamId, ResponseHeaders),

                    {ok, State#state{req_headers=Headers,
                                     content_type=ContentType,
                                     request_encoding=RequestEncoding,
                                     response_encoding=ResponseEncoding,
                                     method=M}};
                _ ->
                    end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"service method not found">>, State)
            end;
        _ ->
            end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"failed parsing path">>, State)
    end.

on_send_push_promise(_, State) ->
    {ok, State}.

on_receive_request_data(Bin, State=#state{data=Data,
                                          request_encoding=Encoding,
                                          method=#method{module=Module,
                                                         function=Function,
                                                         proto=Proto,
                                                         input={Input, _},
                                                         output={_Output, OutputStream}}})->
    try
        Messages = split_frame(Bin, Encoding),
        {_, Data2} = lists:foldl(fun(EncodedMessage, {_IsContinue, DataAcc}) ->
                                         Message = Proto:decode_msg(EncodedMessage, Input),
                                         case Module:Function(Message, DataAcc, State) of
                                             {continue, Data1, _} ->
                                                 {continue, Data1};
                                             {Responses, Data1, _} when is_list(Responses)
                                                                        , OutputStream =:= true ->
                                                 [begin
                                                      send(false, Response, State)
                                                  end || Response <- Responses],
                                                 {continue, Data1};
                                             {Response, Data1, _} ->
                                                 send(false, Response, State),
                                                 {stop, Data1}
                                         end
                                 end, {continue, Data}, Messages),
        {ok, State#state{data=Data2}}
    catch
        throw:{grpc_error, {Status, Message}} ->
            end_stream(Status, Message, State)
    end.

on_request_end_stream(State=#state{method=#method{output={Output, false}}}) ->
    end_stream(State),
    {ok, State};
on_request_end_stream(State=#state{data=Data,
                                   method=#method{module=Module,
                                                  function=Function,
                                                  input={_Input, _},
                                                  output={Output, true}}}) ->
    {Message, _, _} = Module:Function(eos, Data, State),
    send(false, Message, State),
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

send(End, Message, #state{connection_pid=ConnPid,
                          stream_id=StreamId,
                          response_encoding=Encoding,
                          method=#method{proto=Proto,
                                         input={_Input, _},
                                         output={Output, _}}}) ->
    BodyToSend = Proto:encode_msg(Message, Output),
    OutFrame = encode_frame(Encoding, BodyToSend),
    h2_connection:send_body(ConnPid, StreamId, OutFrame, [{send_end_stream, End}]),
    ok.


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
