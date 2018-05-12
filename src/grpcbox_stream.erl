-module(grpcbox_stream).

-include_lib("chatterbox/include/http2.hrl").
-include("grpcbox.hrl").

-behaviour(h2_stream).

-export([send/2,
         send/3,
         send_headers/2,
         add_headers/2,
         add_trailers/2,
         set_trailers/2,
         code_to_status/1,
         error/2,
         ctx/1,
         ctx/2,
         handle_streams/2,
         handle_call/2,
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
                buffer             :: binary(),
                ctx                :: ctx:ctx(),
                req_headers=[]     :: list(),
                full_method        :: binary() | undefined,
                input_ref          :: reference() | undefined,
                callback_pid       :: pid() | undefined,
                connection_pid     :: pid(),
                request_encoding   :: gzip | undefined,
                response_encoding  :: gzip | undefined,
                content_type       :: proto | json | undefined,
                resp_headers=[]    :: list(),
                resp_trailers=[]   :: list(),
                headers_sent=false :: boolean(),
                trailers_sent=false :: boolean(),
                unary_interceptor  :: fun() | undefined,
                stream_interceptor :: fun() | undefined,
                stream_id          :: stream_id(),
                method             :: #method{} | undefined}).

-opaque t() :: #state{}.

-type grpc_status_message() :: unicode:chardata().
-type grpc_status() :: 0..16.
-type grpc_error() :: {grpc_status(), grpc_status_message()}.
-type grpc_error_response() :: {grpc_error, grpc_error()}.

-define(GRPC_ERROR(Status, Message), {grpc_error, {Status, Message}}).
-define(THROW(Status, Message), throw(?GRPC_ERROR(Status, Message))).

init(ConnPid, StreamId, [Socket, AuthFun, UnaryInterceptor, StreamInterceptor]) ->
    process_flag(trap_exit, true),
    {ok, #state{connection_pid=ConnPid,
                stream_id=StreamId,
                buffer = <<>>,
                auth_fun=AuthFun,
                unary_interceptor=UnaryInterceptor,
                stream_interceptor=StreamInterceptor,
                socket=Socket,
                handler=self()}}.

on_receive_request_headers(Headers, State=#state{auth_fun=AuthFun,
                                                 socket=Socket}) ->
    %% proplists:get_value(<<":method">>, Headers) =:= <<"POST">>,
    RequestEncoding = parse_options(<<"grpc-encoding">>, Headers),
    ResponseEncoding = parse_options(<<"grpc-accept-encoding">>, Headers),
    ContentType = parse_options(<<"content-type">>, Headers),

    Metadata =  lists:foldl(fun({K, V}, Acc) ->
                                    case is_reserved_header(K) of
                                        true ->
                                            Acc;
                                        false ->
                                            maps:put(K, maybe_decode_header(K, V), Acc)
                                    end
                            end, #{}, Headers),

    Ctx = case parse_options(<<"grpc-timeout">>, Headers) of
              infinity ->
                  grpcbox_metadata:new_incoming_ctx(Metadata);
              D ->
                  ctx:with_deadline_after(grpcbox_metadata:new_incoming_ctx(Metadata), D, nanosecond)
          end,

    RespHeaders = [{<<":status">>, <<"200">>},
                   {<<"user-agent">>, <<"grpc-erlang/0.1.0">>},
                   {<<"content-type">>, content_type(ContentType)}
                   | response_encoding(ResponseEncoding)],

    FullPath = proplists:get_value(<<":path">>, Headers),
    case string:lexemes(FullPath, "/") of
        [Service, Method] ->
            case ets:lookup(?SERVICES_TAB, {Service, Method}) of
                [M=#method{input={_, InputStreaming}}] ->
                    State1 = State#state{resp_headers=RespHeaders,
                                         req_headers=Headers,
                                         full_method=FullPath,
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
                    end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"Method not found on server">>,
                               State#state{resp_headers=RespHeaders})
            end;
        _ ->
            State1 = State#state{resp_headers=[{<<":status">>, <<"200">>},
                                               {<<"user-agent">>, <<"grpc-erlang/0.1.0">>}]},
            end_stream(?GRPC_STATUS_UNIMPLEMENTED, <<"failed parsing path">>, State1),
            {ok, State1}
    end.

authenticate(_, undefined) ->
    {true, undefined};
authenticate({ok, Cert}, Fun) ->
    Fun(Cert);
authenticate(_, _) ->
    false.

handle_streams(Ref, State=#state{full_method=FullMethod,
                                 stream_interceptor=StreamInterceptor,
                                 method=#method{module=Module,
                                                function=Function,
                                                output={_, false}}}) ->
    case (case StreamInterceptor of
              undefined -> Module:Function(Ref, State);
              _ ->
                  ServerInfo = #{full_method => FullMethod,
                                 service => Module,
                                 input_stream => true,
                                 output_strema => false},
                  StreamInterceptor(Ref, State, ServerInfo, fun Module:Function/2)
          end) of
        {ok, Response, State1} ->
            send(false, Response, State1);
        E={grpc_error, _} ->
            throw(E)
    end;
handle_streams(Ref, State=#state{full_method=FullMethod,
                                 stream_interceptor=StreamInterceptor,
                                 method=#method{module=Module,
                                                function=Function,
                                                output={_, true}}}) ->
    case StreamInterceptor of
        undefined ->
            Module:Function(Ref, State);
        _ ->
            ServerInfo = #{full_method => FullMethod,
                           service => Module,
                           input_stream => true,
                           output_strema => true},
            StreamInterceptor(Ref, State, ServerInfo, fun Module:Function/2)
    end.

on_send_push_promise(_, State) ->
    {ok, State}.

ctx_with_stream(Ctx, Stream) ->
    ctx:set(Ctx, ctx_stream_key, Stream).

from_ctx(Ctx) ->
    ctx:get(Ctx, ctx_stream_key).

on_receive_request_data(Bin, State=#state{request_encoding=Encoding,
                                          input_ref=Ref,
                                          callback_pid=Pid,
                                          unary_interceptor=UnaryInterceptor,
                                          ctx=Ctx,
                                          buffer=Buffer,
                                          full_method=FullMethod,
                                          method=#method{module=Module,
                                                         function=Function,
                                                         proto=Proto,
                                                         input={Input, InputStream},
                                                         output={_Output, OutputStream}}})->
    try
        {NewBuffer, Messages} = split_frame(<<Buffer/binary, Bin/binary>>, Encoding),
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
                                                     Ctx1 = ctx_with_stream(Ctx, StateAcc),
                                                     case (case UnaryInterceptor of
                                                               undefined -> Module:Function(Ctx1, Message);
                                                               _ ->
                                                                   ServerInfo = #{full_method => FullMethod,
                                                                                  service => Module},
                                                                   UnaryInterceptor(Ctx1, Message, ServerInfo, fun Module:Function/2)
                                                           end) of
                                                         {ok, Response, Ctx2} ->
                                                             StateAcc1 = from_ctx(Ctx2),
                                                             send(false, Response, StateAcc1);
                                                         E={grpc_error, _} ->
                                                             throw(E)
                                                     end
                                             end
                                     catch
                                         error:{gpb_error, _} ->
                                             ?THROW(?GRPC_STATUS_INTERNAL, <<"Error parsing request protocol buffer">>)
                                     end
                             end, State, Messages),
        {ok, State1#state{buffer=NewBuffer}}
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
end_stream(_Status, _Message, State=#state{trailers_sent=true}) ->
    {ok, State};
end_stream(Status, Message, State=#state{connection_pid=ConnPid,
                                         stream_id=StreamId,
                                         resp_trailers=Trailers}) ->
    EncodedTrailers = encode_headers(Trailers),
    h2_connection:send_trailers(ConnPid, StreamId, [{<<"grpc-status">>, Status},
                                                    {<<"grpc-message">>, Message} | EncodedTrailers],
                                [{send_end_stream, true}]),
    {ok, State#state{trailers_sent=true}}.

set_trailers(Ctx, Trailers) ->
    State = from_ctx(Ctx),
    ctx_with_stream(Ctx, State#state{resp_trailers=maps:to_list(Trailers)}).

send_headers(State) ->
    send_headers([], State).

send_headers(Ctx, Headers) when is_map(Headers) ->
    State = from_ctx(Ctx),
    send_headers(maps:to_list(grpc_lib:maybe_encode_headers(Headers)), State);

send_headers(_Metadata, State=#state{headers_sent=true}) ->
    State;
send_headers(Metadata, State=#state{connection_pid=ConnPid,
                                    stream_id=StreamId,
                                    resp_headers=Headers,
                                    headers_sent=false}) ->
    MdHeaders = encode_headers(Metadata),
    h2_connection:send_headers(ConnPid, StreamId, Headers++MdHeaders, [{send_end_stream, false}]),
    State#state{headers_sent=true}.

code_to_status(0) -> ?GRPC_STATUS_OK;
code_to_status(1) -> ?GRPC_STATUS_CANCELLED;
code_to_status(2) -> ?GRPC_STATUS_UNKNOWN;
code_to_status(3) -> ?GRPC_STATUS_INVALID_ARGUMENT;
code_to_status(4) -> ?GRPC_STATUS_DEADLINE_EXCEEDED;
code_to_status(5) -> ?GRPC_STATUS_NOT_FOUND;
code_to_status(6) -> ?GRPC_STATUS_ALREADY_EXISTS;
code_to_status(7) -> ?GRPC_STATUS_PERMISSION_DENIED;
code_to_status(8) -> ?GRPC_STATUS_RESOURCE_EXHAUSTED;
code_to_status(9) -> ?GRPC_STATUS_FAILED_PRECONDITION;
code_to_status(10) -> ?GRPC_STATUS_ABORTED;
code_to_status(11) -> ?GRPC_STATUS_OUT_OF_RANGE;
code_to_status(12) -> ?GRPC_STATUS_UNIMPLEMENTED;
code_to_status(13) -> ?GRPC_STATUS_INTERNAL;
code_to_status(14) -> ?GRPC_STATUS_UNAVAILABLE;
code_to_status(15) -> ?GRPC_STATUS_DATA_LOSS;
code_to_status(16) -> ?GRPC_STATUS_UNAUTHENTICATED.

error(Status, Message) ->
    exit(?GRPC_ERROR(Status, Message)).

ctx(#state{handler=Pid}) ->
    h2_stream:call(Pid, ctx).

ctx(#state{handler=Pid}, Ctx) ->
    h2_stream:call(Pid, {ctx, Ctx}).

handle_call(ctx, State=#state{ctx=Ctx}) ->
    {ok, Ctx, State};
handle_call({ctx, Ctx}, State) ->
    {ok, ok, State#state{ctx=Ctx}}.

handle_info({add_headers, Headers}, State) ->
    update_headers(Headers, State);
handle_info({add_trailers, Trailers}, State) ->
    update_trailers(Trailers, State);
handle_info({send_proto, Message}, State) ->
    send(false, Message, State);
handle_info({'EXIT', _, normal}, State) ->
    end_stream(State),
    State;
handle_info({'EXIT', _, {grpc_error, {Status, Message}}}, State) ->
    end_stream(Status, Message, State),
    State;
handle_info({'EXIT', _, _Other}, State) ->
    end_stream(?GRPC_STATUS_UNKNOWN, <<"process exited without reason">>, State),
    State.

add_headers(Headers, #state{handler=Pid}) ->
    Pid ! {add_headers, Headers}.

add_trailers(Ctx, Trailers=#{}) ->
    State=#state{resp_trailers=RespTrailers} = from_ctx(Ctx),
    ctx_with_stream(Ctx, State#state{resp_trailers=maps:to_list(Trailers)++RespTrailers});
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
    {<<>>, lists:reverse(Acc)};
split_frame(<<0, Length:32, Encoded:Length/binary, Rest/binary>>, Encoding, Acc) ->
    split_frame(Rest, Encoding, [Encoded | Acc]);
split_frame(<<1, Length:32, Compressed:Length/binary, Rest/binary>>, Encoding, Acc) ->
    Encoded = case Encoding of
                  gzip ->
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
    split_frame(Rest, Encoding, [Encoded | Acc]);
split_frame(Bin, _Encoding, Acc) ->
    {Bin, lists:reverse(Acc)}.

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

timeout_to_duration(T, <<"H">>) ->
    erlang:convert_time_unit(timer:hours(T), millisecond, nanosecond);
timeout_to_duration(T, <<"M">>) ->
    erlang:convert_time_unit(timer:minutes(T), millisecond, nanosecond);
timeout_to_duration(T, <<"S">>) ->
    erlang:convert_time_unit(T, second, nanosecond);
timeout_to_duration(T, <<"m">>) ->
    erlang:convert_time_unit(T, millisecond, nanosecond);
timeout_to_duration(T, <<"u">>) ->
    erlang:convert_time_unit(T, microsecond, nanosecond);
timeout_to_duration(T, <<"n">>) ->
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


%% TODO: consolidate with grpc_lib. But have to update their header map to support
%% a list of values for a key.

maybe_decode_header(Key, Value) ->
    case binary:longest_common_suffix([Key, <<"-bin">>]) == 4 of
        true ->
            decode_header(Value);
        false ->
            Value
    end.

%% golang gRPC implementation does not add the padding that the Erlang
%% decoder needs...
decode_header(Base64) when byte_size(Base64) rem 4 == 3 ->
    base64:decode(<<Base64/bytes, "=">>);
decode_header(Base64) when byte_size(Base64) rem 4 == 2 ->
    base64:decode(<<Base64/bytes, "==">>);
decode_header(Base64) ->
    base64:decode(Base64).

encode_headers([]) ->
    [];
encode_headers([{Key, Value} | Rest]) ->
     case binary:longest_common_suffix([Key, <<"-bin">>]) == 4 of
         true ->
             [{Key, base64:encode(Value)} | encode_headers(Rest)];
         false ->
             [{Key, Value} | encode_headers(Rest)]
     end.

is_reserved_header(<<"content-type">>) -> true;
is_reserved_header(<<"grpc-message-type">>) -> true;
is_reserved_header(<<"grpc-encoding">>) -> true;
is_reserved_header(<<"grpc-message">>) -> true;
is_reserved_header(<<"grpc-status">>) -> true;
is_reserved_header(<<"grpc-timeout">>) -> true;
is_reserved_header(<<"grpc-status-details-bin">>) -> true;
is_reserved_header(<<"te">>) -> true;
is_reserved_header(_) -> false.
