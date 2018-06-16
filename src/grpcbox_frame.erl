-module(grpcbox_frame).

-export([encode/2,
         split/2]).

-include("grpcbox.hrl").

encode(gzip, Bin) ->
    CompressedBin = zlib:gzip(Bin),
    Length = byte_size(CompressedBin),
    <<1, Length:32, CompressedBin/binary>>;
encode(identity, Bin) ->
    Length = byte_size(Bin),
    <<0, Length:32, Bin/binary>>;
encode(Encoding, _) ->
    throw({error, {unknown_encoding, Encoding}}).

split(Frame, Encoding) ->
    split(Frame, Encoding, []).

split(<<>>, _Encoding, Acc) ->
    {<<>>, lists:reverse(Acc)};
split(<<0, Length:32, Encoded:Length/binary, Rest/binary>>, Encoding, Acc) ->
    split(Rest, Encoding, [Encoded | Acc]);
split(<<1, Length:32, Compressed:Length/binary, Rest/binary>>, Encoding, Acc) ->
    Encoded = case Encoding of
                  gzip ->
                      try zlib:gunzip(Compressed)
                      catch
                          error:data_error ->
                              ?THROW(?GRPC_STATUS_INTERNAL,
                                     <<"Could not decompress but compression algorithm ",
                                       (atom_to_binary(Encoding, utf8))/binary, " is supported">>)
                      end;
                  _ ->
                      ?THROW(?GRPC_STATUS_UNIMPLEMENTED,
                             <<"Compression mechanism ", (atom_to_binary(Encoding, utf8))/binary,
                               " used for received frame not supported">>)
              end,
    split(Rest, Encoding, [Encoded | Acc]);
split(Bin, _Encoding, Acc) ->
    {Bin, lists:reverse(Acc)}.
