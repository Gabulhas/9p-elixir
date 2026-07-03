defmodule Protocolencoder do
  alias Types.QID

  defp type_as_bytes(type) do
    <<type::little-integer-size(8)>>
  end

  defp size_as_bytes(size) do
    <<size::little-integer-size(32)>>
  end

  defp tag_as_bytes(tag) do
    <<tag::little-integer-size(16)>>
  end

  defp build_message(type, tag, payload) do
    first_part = type_as_bytes(type) <> tag_as_bytes(tag) <> payload
    size_bytes = size_as_bytes(4 + byte_size(first_part))

    IO.inspect(size_bytes, label: "BUILD Size Bytes", binaries: :as_binaries)
    IO.inspect(type_as_bytes(type), label: "BUILD Type Bytes", binaries: :as_binaries)
    IO.inspect(tag_as_bytes(tag), label: "BUILD Tag Bytes", binaries: :as_binaries)
    IO.inspect(payload, label: "BUILD payload Bytes", binaries: :as_binaries)
    size_bytes <> first_part
  end

  def encode_message({:rversion, tag, msize, version})
      when is_integer(msize) and is_binary(version) do
    payload = <<
      msize::little-integer-size(32),
      String.length(version)::little-integer-size(16),
      version::binary
    >>

    build_message(101, tag, payload)
  end

  # | **Rattach** | 105 | `qid[13]` | Server returns the Qid of the root directory. |
  def encode_message({:rattach, tag, qid}) do
    payload = encode_qid(qid)
    build_message(105, tag, payload)
  end

  # | **Rwalk** | 111 | `nwqid[2]`, `wqid[13]` (array) | Server confirms successful steps `nwqid` and returns the Qids for each step. |
  def encode_message({:rwalk, tag, nwnmaes, qids}) do
    num_qids = nwnmaes

    qids_bytes = encode_rwalk_qids(qids)

    payload = <<num_qids::little-integer-size(16)>> <> qids_bytes

    build_message(111, tag, payload)
  end

  def encode_message({:rerror, tag, message}) do
    IO.inspect("RERROR: #{message}")

    message = "#{message}"

    payload = <<
      String.length(message)::little-integer-size(16),
      message::binary
    >>

    build_message(107, tag, payload)
  end

  # | **Ropen** | 113 | `qid[13]`, `iounit[4]` | Server confirms open, returns Qid and `iounit` (max I/O chunk size; `0` means no limit). |
  # | **Rcreate** | 115 | `qid[13]`, `iounit[4]` | Server confirms created, returns Qid and `iounit` (max I/O chunk size; `0` means no limit). |
  def encode_message({type, tag, qid, iounit}) when type in [:ropen, :rcreate] do
    payload = encode_qid(qid) <> <<iounit::little-integer-size(32)>>

    code = if type == :ropen, do: 113, else: 115

    build_message(code, tag, payload)
  end

  # | **Rread** | 117 | `count[4]`, `data[count]` | Server returns `count` of bytes actually read, followed by raw `data`. |
  def encode_message({:rread, tag, count, data}) do
    payload = <<count::little-integer-size(32), data::bitstring>>
    build_message(117, tag, payload)
  end

  def encode_message({:rwrite, tag, count}) do
    payload = <<count::little-integer-size(32)>>
    build_message(119, tag, payload)
  end

  # | **Rclunk** | 121 | *(Empty Payload)* | Server confirms `fid` is forgotten. |
  def encode_message({:rclunk, tag}) do
    build_message(121, tag, <<>>)
  end

  defp encode_rwalk_qids(qids) do
    case qids do
      [] -> <<>>
      [head | tl] -> encode_qid(head) <> encode_rwalk_qids(tl)
    end
  end

  defp encode_qid(qid) do
    %QID{type: type, vers: vers, path: path} = qid

    <<
      type::8,
      vers::little-integer-size(32),
      path::little-integer-size(64)
    >>
  end
end
