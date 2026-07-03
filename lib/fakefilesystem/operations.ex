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
      {:ok, new_qid} = generate_qid_for_real_file(expanded_path)
      walk_rec(expanded_path, tail, [new_qid | qids])
    else
      {:error, :unsafe} ->
        {:error, "permission denied"}

      false ->
        if qids == [], do: {:error, "file not found"}, else: {:ok, Enum.reverse(qids), ""}
    end
  end

  def generate_qid_for_real_file(actual_os_path) do
    case File.stat(actual_os_path, time: :posix) do
      {:ok, stat} ->
        qid_type =
          case stat.type do
            :directory -> 0x80
            :regular -> 0x00
            _ -> 0x00
          end

        qid_version = stat.mtime

        qid_path = stat.inode

        {:ok,
         %Types.QID{
           type: qid_type,
           vers: qid_version,
           path: qid_path
         }}

      {:error, _} ->
        {:error, "file doesn't exist"}
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
        {:error, "reading file: #{reason}"}

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
        {:error, "reading file: #{reason}"}
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

  def fake_root do
    Path.absname("./exampleroot")
  end

  def fake_root_qid do
    generate_qid_for_real_file(fake_root())
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
