-module(grpcbox_yaml).

-import(yval, [options/2, list/1, atom/0, port/0, either/2, string/0, ipv4/0,
               any/0, int/0, bool/0, file/0, and_then/2, enum/1, map/3,
               directory/0, term/0, non_neg_int/0]).

-export([validator/0]).

%%%===================================================================
%%% API
%%%===================================================================
-spec validator() -> yval:validator().
validator() ->
    options(#{
        client => client_validator(),
        servers => list(server_validator())
    }, [unique, {return, map}]).

server_validator() ->
    options(#{
        grpc_opts => options(#{
            service_protos => list(atom()),
            services => map(atom(), atom(), [unique, {return, map}]),
            client_cert_dir => directory()
        }, [unique, {return, map}, {required, [service_protos, services]}]),
        listen_opts => options(#{
            port => port(),
            ip => either(string(), ipv4()),
            socket_options => [any()]
        }, [unique, {return, map}, {required, [port]}]),
        pool_opts => options(#{size => int()}, [unique, {return, map}]),
        server_opts => server_opts_validator(),
        transport_opts => options(#{
            ssl => bool(),
            keyfile => file(),
            certfile => file(),
            cacertfile => file()
        }, [unique, {return, map}])
    }, [unique, {return, map}, {required, [grpc_opts, listen_opts]}]).

client_validator() ->
    options(#{
        channels => list(channel_validator())
    }, [unique, {return, map}, {required, [channels]}]).

channel_validator() ->
    and_then(
        options(#{
            name => atom(),
            endpoints => list(endpoint_validator()),
            options => client_option_validator()
        }, [unique, {return, map}, {required, [name, endpoints]}]),
        fun(#{name := Name, endpoints := EP} = Conf) ->
            {Name, EP, maps:get(options, Conf, #{})}
        end
    ).

server_opts_validator() ->
    options(
        #{
            header_table_size => int(),
            enable_push => int(),
            max_concurrent_streams => either(unlimited, non_neg_int()),
            initial_window_size => int(),
            max_frame_size => int(),
            max_header_list_size => either(unlimited, non_neg_int())
        },
        [unique, {return, map}]
    ).

endpoint_validator() ->
    and_then(options(#{
        transport => enum([http, https]),
        host => either(string(), ipv4()),
        port => port()
    }, [unique, {return, map}, {required, [transport, host, port]}]),
        fun(#{transport := Transport, host := Host, port := Port}) ->
            {Transport, Host, Port, []}
        end
    ).

client_option_validator() ->
    options(#{
        balancer => enum([round_robin, random, hash, direct, claim]),
        encoding => either(enum([identity, gzip, deflate, snappy]),  atom()),
        unary_interceptor => interceptor_validator(),
        stream_interceptor => interceptor_validator(),
        stats_handler => atom(),
        sync_start => bool()
    },  [unique, {return, map}]).

interceptor_validator() ->
    and_then(
        options(#{
            module => atom(),
            function => atom(),
            arguments => list(term())
        }, [unique, {return, map}, {required, [module, function]}]),
        fun(#{module := Mod, function := Fun} = Conf) ->
            Interceptor = Mod:Fun(),
            case Conf of
                #{arguments := Args} -> {Interceptor, Args};
                Interceptor -> Interceptor
            end
        end).