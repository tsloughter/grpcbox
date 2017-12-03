grpcbox
=====

Library for creating [grpc](https://grpc.io) servers in Erlang, based on the [chatterbox](https://github.com/joedevivo/chatterbox) http2 server.

Implementing a Service
----

The easiest way to get started is using the plugin, [grpcbox_plugin](https://github.com/tsloughter/grpcbox_plugin):

```
{deps, [grpcbox]}.

{grpc, [{protos, "priv/protos"},
        {gpb_opts, [{module_name_suffix, "_pb"}]}]}.

{plugins, [grpcbox_plugin]}.
```

Currently `grpcbox` and the plugin are a bit picky and the `gpb` options will always include `[use_packages, maps, {i, "."}, {o, "src"}]`.

Assuming the `priv/protos` directory of your application has the `route_guide.proto` found in this repo, `priv/protos/route_guide.proto`, the output from running the plugin will be:

```
$ rebar3 grpc gen
===> Writing src/route_guide_pb.erl
===> Writing src/grpcbox_route_guide_behaviour.erl
```

Test
---

To run the Common Test suite:

```
$ rebar3 ct
```

To run another client implementation to test, in particular the route guide example that comes with the Go client, `google.golang.org/grpc/examples/route_guide/client/client.go`:

```
$ rebar3 as test shell
```

And run the client from your `$GOPATH`:

```
$ bin/client -server_addr 127.0.0.1:8080
```
