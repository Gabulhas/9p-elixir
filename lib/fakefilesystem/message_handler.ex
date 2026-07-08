defmodule Fakefilesystem.MessageHandler do
  def handle({:tversion, msize, _}, tag, _, _) do
    Protocolencoder.encode_message({:rversion, tag, msize, "9P2000"})
  end

  def handle({:tauth, _, _, _}, tag, _, _) do
    IO.puts("tauth Not implemented")
    Protocolencoder.encode_message({:rerror, tag, "not implemented"})
  end

  def handle({:tattach, fid, _, _, _}, tag, fid_store, _) do
    root_path = Fakefilesystem.Operations.fake_root()

    Agent.update(fid_store, fn state ->
      Map.put(state, fid, %{attached: true, path: root_path})
    end)

    {:ok, root_qid} = Fakefilesystem.Operations.fake_root_qid()

    IO.inspect(root_qid)
    Protocolencoder.encode_message({:rattach, tag, root_qid})
  end

  def handle({:twalk, fid, newfid, nwnames, wnames}, tag, fid_store, _) do
    with {:ok, %{path: fid_path}} <- get_fid_info(fid, fid_store),
         {:ok, qids, final_path} <- Fakefilesystem.Operations.walk(fid_path, wnames) do
      if final_path != "" do
        Agent.update(fid_store, fn state ->
          Map.put(state, newfid, %{attached: false, path: final_path})
        end)
      end

      IO.inspect({:rwalk, tag, nwnames, qids, final_path})
      Protocolencoder.encode_message({:rwalk, tag, nwnames, qids})
    else
      nil ->
        Protocolencoder.encode_message({:rerror, tag, "invalid fid"})

      {:error, reason} ->
        Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:topen, fid, %{file_opts: opts}}, tag, fid_store, file_store) do
    with {:ok, %{path: fid_path}} <- get_fid_info(fid, fid_store),
         {:ok, qid} = Fakefilesystem.Operations.get_qid(fid_path) do
      handle_open_file(fid_path, opts, file_store)
      Protocolencoder.encode_message({:ropen, tag, qid, 0})
    else
      nil -> Protocolencoder.encode_message({:rerror, tag, "invalid fid"})
      {:error, reason} -> Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:tcreate, fid, name, perm, %{file_opts: opts}}, tag, fid_store, file_store) do
    with {:ok, %{path: fid_path}} <- get_fid_info(fid, fid_store),
         {:ok, expanded_path} <-
           Fakefilesystem.Operations.create_file_or_directory(fid_path, name, perm),
         {:ok, qid} = Fakefilesystem.Operations.get_qid(expanded_path) do
      Agent.update(fid_store, fn state ->
        Map.put(state, fid, expanded_path)
      end)

      handle_open_file(fid_path, opts, file_store)
      Protocolencoder.encode_message({:rcreate, tag, qid, 0})
    else
      {:error, reason} -> Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:tread, fid, offset, count}, tag, fid_store, file_store) do
    with {:ok, %{path: fid_path}, %{file: file, is_directory: is_directory}} <-
           get_path_and_file(fid, fid_store, file_store) do
      if is_directory do
        case Fakefilesystem.Operations.list_dir(fid_path) do
          {:ok, filenames} ->
            giant_buffer =
              filenames
              |> Enum.map(fn name ->
                full_path = Path.join(fid_path, name)
                {:ok, stat} = Fakefilesystem.Operations.stat(full_path)
                Protocolencoder.encode_stat(stat)
              end)
              |> Enum.join()

            safe_data = extract_safe_dir_chunk(giant_buffer, offset, count)

            Protocolencoder.encode_message({:rread, tag, byte_size(safe_data), safe_data})

          {:error, reason} ->
            Protocolencoder.encode_message({:rerror, tag, reason})
        end
      else
        case Fakefilesystem.Operations.read_file(file, offset, count) do
          {:error, reason} ->
            Protocolencoder.encode_message({:rerror, tag, reason})

          {:ok, data} ->
            IO.puts("Read data from file #{data}")
            Protocolencoder.encode_message({:rread, tag, byte_size(data), data})
        end
      end
    else
      :error ->
        Protocolencoder.encode_message({:rerror, tag, "invalid fid or file not opened"})

      {:error, reason} ->
        Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:twrite, fid, offset, _, data}, tag, fid_store, file_store) do
    with {:ok, _, %{file: file}} <-
           get_path_and_file(fid, fid_store, file_store),
         :ok <- Fakefilesystem.Operations.write_file(file, offset, data) do
      Protocolencoder.encode_message({:rwrite, tag, byte_size(data)})
    else
      :error ->
        Protocolencoder.encode_message({:rerror, tag, "invalid fid or file not opened"})

      {:error, reason} ->
        Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:tclunk, fid}, tag, fid_store, file_store) do
    with {:ok, _, %{file: file}} <-
           get_path_and_file(fid, fid_store, file_store),
         :ok <- Fakefilesystem.Operations.close_file(file) do
      Agent.update(fid_store, fn state ->
        Map.delete(state, fid)
      end)

      Protocolencoder.encode_message({:rclunk, tag})
    else
      nil ->
        Protocolencoder.encode_message({:rerror, tag, "file not open to be closed"})

      :error ->
        Protocolencoder.encode_message({:rerror, tag, "invalid fid or file not opened"})

      {:error, reason} ->
        Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:tremove, fid}, tag, fid_store, file_store) do
    with {:ok, %{path: fid_path}, %{file: file}} <-
           get_path_and_file(fid, fid_store, file_store),
         :ok <-
           Fakefilesystem.Operations.close_file(file) do
      Fakefilesystem.Operations.remove_file(fid_path)

      Agent.update(fid_store, fn state ->
        Map.delete(state, fid)
      end)

      Protocolencoder.encode_message({:rremove, tag})
    else
      nil ->
        Protocolencoder.encode_message({:rerror, tag, "file not open to be removed"})

      :error ->
        Protocolencoder.encode_message({:rerror, tag, "invalid fid or file not opened"})

      {:error, reason} ->
        Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:tstat, fid}, tag, fid_store, _file_store) do
    with {:ok, %{path: fid_path}} <- get_fid_info(fid, fid_store),
         {:ok, stat} <- Fakefilesystem.Operations.stat(fid_path) do
      Protocolencoder.encode_message({:rstat, tag, stat})
    else
      nil -> Protocolencoder.encode_message({:rerror, tag, "invalid fid"})
      {:error, reason} -> Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:twstat, fid, stat}, tag, fid_store, file_store) do
    with {:ok, %{path: fid_path}} <- get_fid_info(fid, fid_store),
         {:ok, path_to_modify} <- Fakefilesystem.Operations.wstat(fid_path, stat) do
      if fid_path != path_to_modify do
        Agent.update(fid_store, fn state ->
          Map.update!(state, fid, fn fid_info ->
            %{fid_info | path: path_to_modify}
          end)
        end)

        Agent.update(file_store, fn state ->
          {file_info, state_without_old_path} = Map.pop(state, fid_path)

          if file_info do
            Map.put(state_without_old_path, path_to_modify, file_info)
          else
            state_without_old_path
          end
        end)
      end

      Protocolencoder.encode_message({:rwstat, tag})
    else
      nil ->
        Protocolencoder.encode_message({:rerror, tag, "invalid fid"})

      {:error, reason} ->
        Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def get_fid_info(fid, fid_store) do
    Agent.get(fid_store, fn state -> Map.fetch(state, fid) end)
  end

  def get_file_from_fid(fid_path, file_store) do
    Agent.get(file_store, fn state -> Map.fetch(state, fid_path) end)
  end

  def get_path_and_file(fid, fid_store, file_store) do
    with {:ok, fid_info} <- get_fid_info(fid, fid_store),
         %{path: fid_path} <- fid_info,
         {:ok, file} <- get_file_from_fid(fid_path, file_store) do
      {:ok, fid_info, file}
    end
  end

  defp handle_open_file(fid_path, opts, file_store) do
    if File.dir?(fid_path) do
      Agent.update(file_store, fn state ->
        Map.put(state, fid_path, %{file: nil, opts: opts, is_directory: true})
      end)
    else
      {:ok, file} = Fakefilesystem.Operations.open_file(fid_path, opts)

      Agent.update(file_store, fn state ->
        Map.put(state, fid_path, %{file: file, opts: opts, is_directory: false})
      end)
    end
  end

  defp extract_safe_dir_chunk(giant_buffer, offset, count) do
    case giant_buffer do
      <<_skip::binary-size(offset), remaining::binary>> ->
        pack_integral_stats(remaining, count, <<>>)

      _ ->
        <<>>
    end
  end

  defp pack_integral_stats(<<>>, _limit, acc), do: acc

  defp pack_integral_stats(buffer, limit, acc) do
    if byte_size(buffer) >= 2 do
      <<stat_size::little-integer-size(16), _rest::binary>> = buffer

      total_struct_size = stat_size + 2

      if byte_size(acc) + total_struct_size <= limit do
        <<this_stat::binary-size(total_struct_size), next_buffer::binary>> = buffer
        pack_integral_stats(next_buffer, limit, acc <> this_stat)
      else
        acc
      end
    else
      acc
    end
  end
end
