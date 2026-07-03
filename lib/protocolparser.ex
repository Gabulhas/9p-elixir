defmodule Protocolparser do
  alias Types.Messages
  import Bitwise

  # Tversion (ID: 100) -> msize[4], version[s]
  def parse_payload(%Messages{type: 100, payload: payload}) do
    <<
      msize::little-integer-size(32),
      str_len::little-integer-size(16),
      version::binary-size(str_len)
    >> = payload

    {:tversion, msize, version}
  end

  # Rversion (ID: 101) -> msize[4], version[s]
  def parse_payload(%Messages{type: 101, payload: payload}) do
    <<
      msize::little-integer-size(32),
      str_len::little-integer-size(16),
      version::binary-size(str_len)
    >> = payload

    {:rversion, msize, version}
  end

  # Tauth (ID: 102) -> afid[4], uname[s], aname[s] 
  def parse_payload(%Messages{type: 102, payload: payload}) do
    <<
      afid::little-integer-size(32),
      uname_size::little-integer-size(16),
      uname::binary-size(uname_size),
      aname_size::little-integer-size(16),
      aname::binary-size(aname_size)
    >> = payload

    {:tauth, afid, uname, aname}
  end

  # Tattach (ID: 104) -> fid[4], afid[4], uname[s], aname[s] 
  def parse_payload(%Messages{type: 104, payload: payload}) do
    <<
      fid::little-integer-size(32),
      afid::little-integer-size(32),
      uname_size::little-integer-size(16),
      uname::binary-size(uname_size),
      aname_size::little-integer-size(16),
      aname::binary-size(aname_size)
    >> = payload

    {:tattach, fid, afid, uname, aname}
  end

  # Twalk (ID: 110) -> fid[4], newfid[4], nwname[2], wname[s] (array) | Client navigates starting from fid, creates newfid. nwname is step count. wname are the folder names. |
  def parse_payload(%Messages{type: 110, payload: payload}) do
    <<
      fid::little-integer-size(32),
      newfid::little-integer-size(32),
      nwname::little-integer-size(16),
      strings::binary
    >> = payload

    wnames = parse_wnames(strings, nwname, [])

    {:twalk, fid, newfid, nwname, wnames}
  end

  # Topen (ID: 112) -> fid[4], mode[1]
  def parse_payload(%Messages{type: 112, payload: payload}) do
    <<
      fid::little-integer-size(32),
      mode::little-integer-size(8)
    >> = payload

    {:topen, fid, parse_9p_mode(mode)}
  end

  # Tcreate (ID: 115) -> fid[4], name[s], perm[4], mode[1] 
  def parse_payload(%Messages{type: 114, payload: payload}) do
    <<
      fid::little-integer-size(32),
      str_len::little-integer-size(16),
      name::binary-size(str_len),
      perm::little-integer-size(32),
      mode::little-integer-size(8)
    >> = payload

    {:tcreate, fid, name, perm, parse_9p_mode(mode)}
  end

  # Tread (ID: 116) -> fid[4], offset[8], count[4]
  def parse_payload(%Messages{type: 116, payload: payload}) do
    <<
      fid::little-integer-size(32),
      offset::little-integer-size(64),
      count::little-integer-size(32)
    >> = payload

    {:tread, fid, offset, count}
  end

  #  **Twrite** | 118 | `fid[4]`, `offset[8]`, `count[4]`, `data[count]` | Client writes `count` bytes of `data` to `fid` at `offset`. |
  def parse_payload(%Messages{type: 118, payload: payload}) do
    <<
      fid::little-integer-size(32),
      offset::little-integer-size(64),
      count::little-integer-size(32),
      data::bitstring
    >> = payload

    {:twrite, fid, offset, count, data}
  end

  # | **Tclunk** | 120 | `fid[4]` | Client closes the file. Server must forget the `fid`. |
  def parse_payload(%Messages{type: 120, payload: payload}) do
    <<fid::little-integer-size(32)>> = payload
    {:tclunk, fid}
  end

  # Catch-all for unimplemented messages so your server doesn't crash
  def parse_payload(%Messages{type: type}) do
    IO.puts("Unhandled message type: #{type}")
    :unhandled
  end

  defp parse_wnames(_binary, 0, acc) do
    Enum.reverse(acc)
  end

  defp parse_wnames(binary, count, acc) do
    <<
      str_len::little-integer-size(16),
      str::binary-size(str_len),
      rest::binary
    >> = binary

    parse_wnames(rest, count - 1, [str | acc])
  end

  @doc """
  Converts a 9P mode byte into Elixir File.open/2 options.
  Returns a map so you also know if you need to delete the file on Tclunk.
  """
  def parse_9p_mode(mode_byte) do
    # Extract the bits
    access = mode_byte &&& 0x03
    trunc? = (mode_byte &&& 0x10) != 0
    rclose? = (mode_byte &&& 0x40) != 0

    # We ALWAYS use :binary for 9P so Elixir doesn't corrupt raw bytes with UTF-8 checks
    base_opts = [:binary]

    # Map 9P intent to Elixir File.open flags
    file_opts =
      case {access, trunc?} do
        {0, _} ->
          # OREAD
          [:read | base_opts]

        {1, true} ->
          # OWRITE + OTRUNC (Elixir's :write truncates by default)
          [:write | base_opts]

        {1, false} ->
          # OWRITE (Adding :read prevents Elixir from truncating!)
          [:read, :write | base_opts]

        {2, _} ->
          # ORDWR
          [:read, :write | base_opts]

        {3, _} ->
          # OEXEC (Treated as read-only)
          [:read | base_opts]
      end

    %{
      file_opts: file_opts,
      remove_on_close: rclose?,
      manual_truncate_required: access == 2 and trunc?
    }
  end
end
