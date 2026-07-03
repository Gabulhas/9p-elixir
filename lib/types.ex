defmodule Types.Common do
  # 1 byte
  @type uint8 :: 0..255
  # 2 bytes
  @type uint16 :: 0..65535
  # 4 bytes
  @type uint32 :: 0..4_294_967_295
  # 8 bytes
  @type uint64 :: 0..18_446_744_073_709_551_615

  @type fid :: uint32() | :nofid
end

defmodule Types.Messages do
  defstruct [:size, :type, :tag, :payload]

  @type t :: %__MODULE__{
          size: Types.Common.uint32(),
          type: Types.Common.uint8(),
          tag: Types.Common.uint16() | :notag,
          payload: binary()
        }
end

defmodule Types.QID do
  defstruct [:type, :vers, :path]

  @type t :: %__MODULE__{
          type: Types.Common.uint8(),
          vers: Types.Common.uint32(),
          path: Types.Common.uint64()
        }
end
