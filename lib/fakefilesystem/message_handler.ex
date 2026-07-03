defmodule Fakefilesystem.MessageHandler do
  def handle({:tversion, msize, _}, tag) do
    Protocolencoder.encode_message({tag, msize, "9P2000"})
  end

  def handle({:tauth, _, _, _}, tag) do
    IO.puts("tauth Not implemented")
    Protocolencoder.encode_message({:rerror, tag, "not implemented"})
  end

  def handle({:tattach, fid, _, _, _}, tag) do
    root_path = Fakefilesystem.fake_root()

    Agent.update(fid_store, fn state ->
      Map.put(state, fid, %{attached: true, path: root_path})
    end)

    {:ok, root_qid} = Fakefilesystem.fake_root_qid()

    IO.inspect(root_qid)
    Protocolencoder.encode_message({:rattach, tag, root_qid})
  end

  def handle({:twalk, fid, newfid, nwnames, wnames}, tag) do
    with %{path: fid_path} <- Agent.get(fid_store, fn state -> Map.get(state, fid) end),
         {:ok, qids, final_path} <- Fakefilesystem.walk(fid_path, wnames) do
      if final_path != "" do
        Agent.update(fid_store, fn state ->
          Map.put(state, newfid, %{attached: false, path: final_path})
        end)
      end

      Protocolencoder.encode_message({:rwalk, tag, nwnames, qids})
    else
      nil ->
        Protocolencoder.encode_message({:rerror, tag, "invalid fid"})
    end

    def handle({:error, reason}, tag) do
      Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:topen, fid, %{file_opts: opts}}, tag) do
    with %{path: fid_path} <- Agent.get(fid_store, fn state -> Map.get(state, fid) end),
         fid_path != nil,
         {:ok, qid} = Fakefilesystem.generate_qid_for_real_file(fid_path) do
      handle_open_file(fid_path, opts, file_store)
      Protocolencoder.encode_message({:ropen_or_rcreate, tag, :ropen, qid, 0})
    else
    end

    def handle({:error, reason}, tag) do
      Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:tcreate, fid, name, perm, %{file_opts: opts}}, tag) do
    with %{path: fid_path} <- Agent.get(fid_store, fn state -> Map.get(state, fid) end),
         {:ok, expanded_path} <- Fakefilesystem.create_file_or_directory(fid_path, name, perm),
         {:ok, qid} = Fakefilesystem.generate_qid_for_real_file(expanded_path) do
      Agent.update(fid_store, fn state ->
        Map.put(state, fid, expanded_path)
      end)

      handle_open_file(fid_path, opts, file_store)
      Protocolencoder.encode_message({:ropen_or_rcreate, tag, :rcreate, qid, 0})
    else
    end

    def handle({:error, reason}, tag) do
      Protocolencoder.encode_message({:rerror, tag, "#{reason}"})
    end
  end

  def handle({:tread, fid, offset, count}, tag) do
    with {:ok, %{path: fid_path}} <-
           Agent.get(fid_store, fn state -> Map.fetch(state, fid) end),
         {:ok, %{file: file}} <-
           Agent.get(file_store, fn state -> Map.fetch(state, fid_path) end),
         {:ok, data} <- Fakefilesystem.read_file(file, offset, count) do
      IO.puts("Read data from file #{data}")
      IO.inspect(data)
      IO.inspect(File.read(fid_path))

      Protocolencoder.encode_message({:rread, byte_size(data), data})
    else
      :error ->
        Protocolencoder.encode_message({:rerror, tag, "invalid fid or file not opened"})
    end

    def handle({:error, reason}, tag) do
      Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:twrite, fid, offset, _, data}, tag) do
    with {:ok, %{path: fid_path}} <-
           Agent.get(fid_store, fn state -> Map.fetch(state, fid) end),
         IO.inspect(fid_path),
         {:ok, %{file: file}} <-
           Agent.get(file_store, fn state -> Map.fetch(state, fid_path) end),
         IO.inspect(file),
         :ok <- Fakefilesystem.write_file(file, offset, data) do
      Protocolencoder.encode_message({:rwrite, tag, byte_size(data)})
    else
      :error ->
        Protocolencoder.encode_message({:rerror, tag, "invalid fid or file not opened"})
    end

    def handle({:error, reason}, tag) do
      Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end

  def handle({:tclunk, fid}, tag) do
    with {:ok, %{path: fid_path}} <-
           Agent.get(fid_store, fn state -> Map.fetch(state, fid) end),
         {:ok, %{file: file}} <-
           Agent.get(file_store, fn state -> Map.fetch(state, fid_path) end),
         :ok <- Fakefilesystem.close_file(file) do
      Agent.update(fid_store, fn state ->
        Map.delete(state, fid)
      end)

      Protocolencoder.encode_message({:rclunk, tag})
    else
      nil ->
        Protocolencoder.encode_message({:rerror, tag, "file not open to be closed"})
    end

    def handle({:error, reason}, tag) do
      Protocolencoder.encode_message({:rerror, tag, reason})
    end
  end
end
