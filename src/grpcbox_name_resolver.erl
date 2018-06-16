-module(grpcbox_name_resolver).

-export([resolve/1]).

%% dns:///localhost
%% ipv4:///127.0.0.1

resolve(Name) ->
    case uri_string:parse(Name) of
        #{scheme := _Scheme,
          host := _Authority,
          port := Port,
          path := Endpoint} ->
            {Endpoint, Port};
        _ ->
            {"127.0.0.1", 8080}
    end.
