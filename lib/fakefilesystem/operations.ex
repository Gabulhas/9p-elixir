defmodule Fakefilesystem.Operations do
  import Bitwise

  defp to_safe(path) do
    expanded_path = Path.expand(path)

    if String.starts_with?(expanded_path, fake_root()) do
      {:ok, expanded_path}
    else
      {:error, :unsafe}
    end
  end

  def walk(starting_point, steps) do
    walk_rec(starting_point, steps, [])
  end

  defp walk_rec(current_path, [], qids) do
    {:ok, Enum.reverse(qids), current_path}
  end

  defp walk_rec(current_path, [head | tail], qids) do
    raw_new_path = Path.join(current_path, head)

    with {:ok, expanded_path} <- to_safe(raw_new_path),
         true <- File.exists?(expanded_path) do
      {:ok, new_qid} = get_qid(expanded_path)
      walk_rec(expanded_path, tail, [new_qid | qids])
    else
      {:error, :unsafe} ->
        {:error, "permission denied"}

      false ->
        if qids == [], do: {:error, "file not found"}, else: {:ok, Enum.reverse(qids), ""}
    end
  end

  def open_file(path, mode) do
    with {:ok, expanded_path} <- to_safe(path),
         {:ok, file} <- File.open(expanded_path, mode) do
      {:ok, file}
    else
      {:error, :unsafe} ->
        {:error, "permission denied"}

      {:error, :eacces} ->
        {:error, "invalid permission"}

      {:error, :enoent} ->
        {:error, "file does not exist"}

      {:error, unknown_reason} ->
        {:error, "failed to open: #{inspect(unknown_reason)}"}
    end
  end

  def read_file(file) do
    case File.read(file) do
      {:error, reason} ->
        {:error, "reading file '#{file}': #{reason}"}

      result ->
        result
    end
  end

  def read_file(file, offset, count) do
    case :file.pread(file, offset, count) do
      {:ok, data} ->
        {:ok, data}

      :eof ->
        {:ok, <<>>}

      {:error, reason} ->
        {:error, "reading file '#{file}': #{reason}"}
    end
  end

  def create_file_or_directory(parent, name, perm) do
    raw_new_path = Path.join(parent, name)

    with {:ok, expanded_path} <- to_safe(raw_new_path),
         false <- File.exists?(expanded_path) do
      # 0x80000000 (DMDIR): Create a directory instead of a regular file.
      # 0x40000000 (DMAPPEND): Create an append-only file.
      # 0x20000000 (DMEXCL): Create an exclusive-use file (Plan 9's version of a file lock).
      # 0x00000000: Just a regular, normal file.
      is_dir? = (perm &&& 0x80000000) != 0

      if is_dir? do
        {File.mkdir(expanded_path), expanded_path}
      else
        {File.touch(expanded_path), expanded_path}
      end
    else
      true ->
        {:error, "file already exists"}

      {:error, :unsafe} ->
        {:error, "permission denied"}
    end
  end

  def write_file(file, offset, data) do
    with {:ok, _} <- :file.position(file, offset),
         :ok <- :file.write(file, data),
         {:ok, _} <- :file.position(file, {:bof, 0}) do
      :ok
    else
      {:error, error} ->
        {:error, "writting to file #{error}"}
    end
  end

  def close_file(file) do
    :file.close(file)
  end

  def remove_file(file_or_dir) do
    :file.del_dir_r(file_or_dir)
  end

  def get_qid(fid_path) do
    with {:ok, %Types.Stat{qid: qid}} <- stat(fid_path) do
      {:ok, qid}
    end
  end

  def stat(fid_path) do
    case File.stat(fid_path, time: :posix) do
      {:ok, stat} ->
        qid_type = if stat.type == :directory, do: 0x80, else: 0x00

        qid = %Types.QID{
          type: qid_type,
          vers: stat.mtime,
          path: stat.inode
        }

        length = if stat.type == :directory, do: 0, else: stat.size
        mode = if stat.type == :directory, do: 0x800001FF, else: 0x01B6

        {:ok,
         %Types.Stat{
           size: 0,
           type: 0,
           dev: 0,
           qid: qid,
           mode: mode,
           atime: stat.atime,
           mtime: stat.mtime,
           length: length,
           name: Path.basename(fid_path),
           uid: "root",
           gid: "root",
           muid: "root"
         }}

      {:error, reason} ->
        {:error, "failed to stat file: #{inspect(reason)}"}
    end
  end

  @dont_touch_32 0xFFFFFFFF
  @dont_touch_64 0xFFFFFFFFFFFFFFFF

  def wstat(current_path, %Types.Stat{} = new_stat) do
    path_to_modify = current_path

    path_to_modify =
      if new_stat.name != "" do
        new_full_path = Path.join(Path.dirname(path_to_modify), new_stat.name)

        case File.rename(path_to_modify, new_full_path) do
          :ok -> new_full_path
          {:error, _} -> path_to_modify
        end
      else
        path_to_modify
      end

    if new_stat.mode != @dont_touch_32 do
      unix_perms = new_stat.mode &&& 0x1FF
      File.chmod(path_to_modify, unix_perms)
    end

    if new_stat.length != @dont_touch_64 do
      {:ok, file_info} = :file.read_file_info(path_to_modify)
      new_info = process_file_info_record(file_info, new_stat.length)
      :file.write_file_info(path_to_modify, new_info)
    end

    {:ok, path_to_modify}
  end

  defp process_file_info_record(info, new_length) do
    put_elem(info, 1, new_length)
  end

  def list_dir(dir_path) do
    case File.ls(dir_path) do
      {:ok, files} -> {:ok, files}
      {:error, reason} -> {:error, "failed to list directory: #{inspect(reason)}"}
    end
  end

  def fake_root do
    Path.absname("./exampleroot")
  end

  def fake_root_qid do
    get_qid(fake_root())
  end

  def true_file_path(fake_path) do
    raw_new_path = Path.join(fake_root(), fake_path)

    with {:ok, expanded_path} <- to_safe(raw_new_path),
         true <- File.exists?(expanded_path) do
      {:ok, expanded_path}
    else
      false ->
        {:error, "file not found"}

      {:error, :unsafe} ->
        {:error, "permission denied"}
    end
  end
end
