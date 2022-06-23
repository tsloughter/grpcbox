%%%-------------------------------------------------------------------
%% @doc Behaviour to implement for grpc service grpc.reflection.v1alpha.ServerReflection.
%% @end
%%%-------------------------------------------------------------------

%% this module was generated and should not be modified manually

-module(grpcbox_reflection_bhvr).

%% 
-callback server_reflection_info(reference(), grpcbox_stream:t()) ->
    ok | grpcbox_stream:grpc_error_response().

