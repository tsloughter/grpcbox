-module(grpcbox_trace).

-export([unary/4,
         stream/4]).

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
        oc_trace:finish_span(oc_tace:from_ctx(Ctx2))
    end.

%%

trace_context_from_ctx(Ctx) ->
    Metadata = grpcbox_metadata:from_incoming_ctx(Ctx),
    case maps:get(<<"grpc-trace-bin">>, Metadata, undefined) of
        undefined ->
            %% oc_trace:with_span_ctx(Ctx, undefined);
            Ctx;
        Bin ->
            try
                oc_trace:with_span_ctx(Ctx, oc_span_ctx_binary:decode(Bin))
            catch
                _:_ ->
                    %% oc_trace:with_span_ctx(Ctx, undefined)
                    Ctx
            end
    end.
