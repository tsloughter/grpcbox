%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.reflection.v1alpha.ServerReflection.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated on 2019-03-09T00:28:46+00:00 and should not be modified manually

-module(grpcbox_reflection_bhvr).

%% @doc 
-callback server_reflection_info(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

