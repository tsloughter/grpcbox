-module(grpcbox_chain_interceptor).

-export([unary/1]).

unary(InterceptorList) ->
    create_chain_funs(InterceptorList).

create_chain_funs([I1]) ->
    fun(Ctx, Message, ServerInfo, Handler) ->
            I1(Ctx, Message, ServerInfo, Handler)
    end;
create_chain_funs([I1 | Rest]) ->
    fun(Ctx, Message, ServerInfo, Handler) ->
            I1(Ctx, Message, ServerInfo, create_chain_handlers(Rest, ServerInfo, Handler))
    end.

create_chain_handlers([I], ServerInfo, Handler) ->
    fun(Ctx, Message) ->
            I(Ctx, Message, ServerInfo, Handler)
    end;
create_chain_handlers([I | Rest], ServerInfo, Handler) ->
    fun(Ctx, Message) ->
            I(Ctx, Message, ServerInfo, create_chain_handlers(Rest, ServerInfo, Handler))
    end.
