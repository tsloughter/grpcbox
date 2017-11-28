-define(SERVICES_TAB, services_table).

-record(method, {key      :: {unicode:chardata(), unicode:chardata()},
                 proto    :: module(),
                 module   :: module(),
                 function :: atom(),
                 input    :: {term(), boolean()},
                 output   :: {term(), boolean()},
                 opts     :: [term()]}).
