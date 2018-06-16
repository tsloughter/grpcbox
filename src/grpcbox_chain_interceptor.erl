-module(grpcbox_chain_interceptor).

-export([stream_chain/1,
         unary_client/1,
         new_stream_client/1,
         send_client/1,
         recv_client/1,
         unary/1,
         stream/1]).

stream_chain(L) ->
    #{new_stream => new_stream_client(L),
      send_msg => send_client(L),
      recv_msg => recv_client(L)}.

new_stream_client([I]) ->
    fun(Ctx, Channel, Path, Def, Handler, Options) ->
            I:new_stream(Ctx, Channel, Path, Def, Handler, Options)
    end;
new_stream_client([I | Rest]) ->
    fun(Ctx, Channel, Path, Def, Handler, Options) ->
            I:new_stream(Ctx, Channel, Path, Def, create_new_stream_fun(Rest, Handler), Options)
    end.

create_new_stream_fun([I], Handler) ->
    fun(Ctx, Channel, Path, Def, Options) ->
            I:new_stream(Ctx, Channel, Path, Def, Handler, Options)
    end;
create_new_stream_fun([I | Rest], Handler) ->
    fun(Ctx, Channel, Path, Def, Options) ->
            I:new_stream(Ctx, Channel, Path, Def, create_new_stream_fun(Rest, Handler), Options)
    end.

send_client([I]) ->
    fun(Stream, Handler, Input) ->
            I:send_msg(Stream, Handler, Input)
    end;
send_client([I | Rest]) ->
    fun(Stream, Handler, Input) ->
            I:send_msg(Stream, create_send_fun(Rest, Handler), Input)
    end.

create_send_fun([I], Handler) ->
    fun(Stream, Input) ->
            I:send_msg(Stream, Handler, Input)
    end;
create_send_fun([I | Rest], Handler) ->
    fun(Stream, Input) ->
            I:send_msg(Stream, create_new_stream_fun(Rest, Handler), Input)
    end.

recv_client([I]) ->
    fun(Stream, Handler, Timeout) ->
            I:recv_msg(Stream, Handler, Timeout)
    end;
recv_client([I | Rest]) ->
    fun(Stream, Handler, Timeout) ->
            I:recv_msg(Stream, create_recv_fun(Rest, Handler), Timeout)
    end.

create_recv_fun([I], Handler) ->
    fun(Stream, Timeout) ->
            I:recv_msg(Stream, Handler, Timeout)
    end;
create_recv_fun([I | Rest], Handler) ->
    fun(Stream, Timeout) ->
            I:recv_msg(Stream, create_new_stream_fun(Rest, Handler), Timeout)
    end.

unary_client(InterceptorList) ->
    create_client_interceptor_fun(InterceptorList).

create_client_interceptor_fun([I]) ->
    fun(Ctx, Channel, Handler, Path, Input, Def, Options) ->
            I(Ctx, Channel, Handler, Path, Input, Def, Options)
    end;
create_client_interceptor_fun([I | Rest]) ->
    fun(Ctx, Channel, Handler, Path, Input, Def, Options) ->
            I(Ctx, Channel, create_client_handler_fun(Rest, Channel, Handler, Path, Def, Options),
              Path, Input, Def, Options)
    end.

create_client_handler_fun([I], Channel, Handler, Path, Def, Options) ->
    fun(Ctx, Input) ->
            I(Ctx, Channel, Handler, Path, Input, Def, Options)
    end;
create_client_handler_fun([I | Rest], Channel, Handler, Path, Def, Options) ->
    fun(Ctx, Input) ->
            I(Ctx, Channel, create_client_handler_fun(Rest, Channel, Handler, Path, Def, Options),
              Path, Input, Def, Options)
    end.

unary(InterceptorList) ->
    create_interceptor_fun(InterceptorList).

%% right now stream and unary have the same arity and ServerInfo argument so we build them the same
%% this may change in the future
stream(InterceptorList) ->
    create_interceptor_fun(InterceptorList).

%% the chain interceptor creates an interceptor which for the handler receives a fun/2 that
%% calls the next interceptor, which has a handler fun/2 that has the interceptor after that,
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
