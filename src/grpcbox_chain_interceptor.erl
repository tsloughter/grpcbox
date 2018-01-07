-module(grpcbox_chain_interceptor).

-export([unary/1,
         stream/1]).

unary(InterceptorList) ->
    create_interceptor_fun(InterceptorList).

%% right now stream and unary have the same arity and ServerInfo argument so we build them the same
%% this may change in the future
stream(InterceptorList) ->
    create_interceptor_fun(InterceptorList).

%% the chain interceptor creates an interceptor which for the handler receives a fun/2 that
%% calls the next interceptor, which has a handler fun/2 that has interceptor after that,
%% and so on until the last which has the service method handler as usual.

create_interceptor_fun([I]) ->
    fun(Arg1, Arg2, ServerInfo, Handler) ->
            I(Arg1, Arg2, ServerInfo, Handler)
    end;
create_interceptor_fun([I | Rest]) ->
    fun(Arg1, Arg2, ServerInfo, Handler) ->
            I(Arg1, Arg2, ServerInfo, create_handler_fun(Rest, ServerInfo, Handler))
    end.

create_handler_fun([I], ServerInfo, Handler) ->
    fun(Arg1, Arg2) ->
            I(Arg1, Arg2, ServerInfo, Handler)
    end;
create_handler_fun([I | Rest], ServerInfo, Handler) ->
    fun(Arg1, Arg2) ->
            I(Arg1, Arg2, ServerInfo, create_handler_fun(Rest, ServerInfo, Handler))
    end.
