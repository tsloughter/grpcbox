%% interceptors for opencensus tracing and stats
-module(grpcbox_trace).

-export([%% server side
         unary/4,
         stream/4,

         %% unary client interceptor
         unary_client/7,

         %% client streaminig interceptors
         new_stream/6,
         send_msg/3,
         recv_msg/3]).

unary_client(Ctx, _Channel, Handler, FullMethod, Input, _Def, _Options) ->
    Ctx1 = oc_trace:with_child_span(Ctx,
                                    FullMethod,
                                    #{}),
    try
        Handler(Ctx1, Input)
    after
        oc_trace:finish_span(oc_trace:from_ctx(Ctx1))
    end.

new_stream(Ctx, Channel, Path, Def, Streamer, Options) ->
    {ok, S} = Streamer(Ctx, Channel, Path, Def, Options),
    {ok, #{client_stream => S}}.

send_msg(#{client_stream := ClientStream}, Streamer, Input) ->
    Streamer(ClientStream, Input).

recv_msg(#{client_stream := ClientStream}, Streamer, Input) ->
    Streamer(ClientStream, Input).

unary(Ctx, Message, _ServerInfo=#{full_method := FullMethod}, Handler) ->
    Ctx1 = trace_context_from_ctx(Ctx),
    Ctx2 = oc_trace:with_child_span(Ctx1,
                                    FullMethod,
                                    #{remote_parent => true}),
    try
        Handler(Ctx2, Message)
    after
        oc_trace:finish_span(oc_trace:from_ctx(Ctx2))
    end.

stream(Ref, Stream, _ServerInfo=#{full_method := FullMethod}, Handler) ->
    Ctx = grpcbox_stream:ctx(Stream),
    Ctx1 = trace_context_from_ctx(Ctx),
    Ctx2 = oc_trace:with_child_span(Ctx1,
                                    FullMethod,
                                    #{remote_parent => true}),
    try
        grpcbox_stream:ctx(Stream, Ctx2),
        Handler(Ref, Stream)
    after
        oc_trace:finish_span(oc_trace:from_ctx(Ctx2))
    end.

%%

trace_context_from_ctx(Ctx) ->
    Metadata = grpcbox_metadata:from_incoming_ctx(Ctx),
    case maps:get(<<"grpc-trace-bin">>, Metadata, undefined) of
        undefined ->
            Ctx;
        Bin ->
            try
                oc_trace:with_span_ctx(Ctx, oc_propagation_binary:decode(Bin))
            catch
                _:_ ->
                    Ctx
            end
    end.
