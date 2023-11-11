Benchmark
=========
Utilities for benchmarking grpcbox. The used protocol is compatible with the one defined in [grpc](https://github.com/grpc/grpc/blob/master/src/proto/grpc/testing/benchmark_service.proto) and for example the Go benchmark client and server can be used against grpcbox.

Grpcbox benchmark server
------------------------
To run the grpcbox benchmark server:

```
$ rebar3 as benchmark shell
```

Server options can be changed in `benchmark/config/sys.config`

Grpcbox benchmark client
------------------------
The benchmark client is implemented as a Common Test. First set test parameters in `benchmark/config/test.config`. The available parameters are described in the file. Also the chatterbox client options can be set. After setting test parameters and starting a server to test against, run the grpcbox benchmark client:

```
$ rebar3 as benchmark ct --verbose
```

The --verbose option needs to be set for the measurements to be printed out.

Go benchmark client and server
------------------------------
Grpcbox benchmark is compatible with the Go benchmark client and server.

To build the Go client and server:

```
$ go build -o $GOPATH/bin/go-grpc-benchmark-client <path-to-grpc-go>/benchmark/client
$ go build -o $GOPATH/bin/go-grpc-benchmark-server <path-to-grpc-go>/benchmark/server
```

Example of running the Go benchmark server:

```
$ go-grpc-benchmark-server -port 8080 -test_name mytest
```

Example of running the Go benchmark client:

```
$ go-grpc-benchmark-client -port 8080 -test_name mytest -d 10 -w 1 -r 100 -c 1 -rpc_type unary -req 1 -resp 1
```
