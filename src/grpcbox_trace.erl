-module(grpcbox_trace).

-export([unary/4]).

unary(Ctx, Message, _ServerInfo=#{full_method := FullMethod}, Handler) ->
    {ok, TraceContext} = trace_context_from_ctx(Ctx),
    Span = opencensus:start_span(FullMethod, opencensus:start_trace(TraceContext)),
    try

        Handler(ctx:set(Ctx, active_span, Span), Message)
    after
        opencensus:finish_span(Span)
    end.

%%

trace_context_from_ctx(Ctx) ->
    Metadata = grpcbox_metadata:from_incoming_ctx(Ctx),
    case maps:get(<<"grpc-trace-bin">>, Metadata, undefined) of
        undefined ->
            undefined;
        Bin ->
            try
                oc_trace_context_binary:decode(Bin)
            catch
                _:_ ->
                    undefined
            end
    end.
