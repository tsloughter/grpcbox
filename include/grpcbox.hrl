-record(method, {key      :: {unicode:chardata() | '$1', unicode:chardata() | '_'} | '_',
                 proto    :: module() | '$1' | '_',
                 module   :: module() | '_',
                 function :: atom() | '_',
                 input    :: {term(), boolean()} | '_',
                 output   :: {term(), boolean()} | '_',
                 opts     :: [term()] | '_'}).

%% service definition
-record(grpcbox_def, {service :: atom(),
                      message_type = <<>> :: binary(),
                      marshal_fun :: fun((map()) -> binary()),
                      unmarshal_fun :: fun((binary()) -> map())}).

-define(CHANNELS_TAB, channels_table).

-define(GRPC_STATUS_OK, <<"0">>).
-define(GRPC_STATUS_CANCELLED, <<"1">>).
-define(GRPC_STATUS_UNKNOWN, <<"2">>).
-define(GRPC_STATUS_INVALID_ARGUMENT, <<"3">>).
-define(GRPC_STATUS_DEADLINE_EXCEEDED, <<"4">>).
-define(GRPC_STATUS_NOT_FOUND, <<"5">>).
-define(GRPC_STATUS_ALREADY_EXISTS , <<"6">>).
-define(GRPC_STATUS_PERMISSION_DENIED, <<"7">>).
-define(GRPC_STATUS_RESOURCE_EXHAUSTED, <<"8">>).
-define(GRPC_STATUS_FAILED_PRECONDITION, <<"9">>).
-define(GRPC_STATUS_ABORTED, <<"10">>).
-define(GRPC_STATUS_OUT_OF_RANGE, <<"11">>).
-define(GRPC_STATUS_UNIMPLEMENTED, <<"12">>).
-define(GRPC_STATUS_INTERNAL, <<"13">>).
-define(GRPC_STATUS_UNAVAILABLE, <<"14">>).
-define(GRPC_STATUS_DATA_LOSS, <<"15">>).
-define(GRPC_STATUS_UNAUTHENTICATED, <<"16">>).

-define(GRPC_ERROR(Status, Message), {grpc_error, {Status, Message}}).
-define(THROW(Status, Message), throw(?GRPC_ERROR(Status, Message))).
