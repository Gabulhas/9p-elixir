defmodule P9serverTest do
  use ExUnit.Case

  setup do
    port = 4001
    Task.start(fn -> P9server.start(port) end)

    Process.sleep(100)

    %{port: port}
  end

  @p9_cmd "/Users/guilhermelopes/gitdownloads/plan9port/bin/9p"

  # test "client can read multiple files", %{port: port} do
  #  files = ["/file1.txt", "/folder/file2.txt", "/folder/nested_folder/file3.txt"]

  #  Enum.each(files, fn file ->
  #    {output, exit_code} =
  #      System.cmd(@p9_cmd, [
  #        "-a",
  #        "tcp!127.0.0.1!#{port}",
  #        "read",
  #        file
  #      ])

  #    {:ok, path} = Fakefilesystem.true_file_path(file)
  #    {:ok, data} = Fakefilesystem.read_file(path)

  #    assert exit_code == 0
  #    assert data == output
  #  end)
  # end

  test "client can write to multiple files", %{port: port} do
    files = [
      {"/file4.txt", "I"},
      {"/folder/file5.txt", "am"},
      {"/folder/nested_folder/file6.txt", "guilherme"}
    ]

    tmp_path = "/tmp/test_payload.tmp"

    Enum.each(files, fn {file, text} ->
      File.write!(tmp_path, text)

      {output, exit_code} =
        System.cmd("sh", [
          "-c",
          "#{@p9_cmd} -a tcp!127.0.0.1!#{port} write #{file} < #{tmp_path}"
        ])

      case Fakefilesystem.true_file_path(file) do
        {:ok, path} ->
          {:ok, data} = Fakefilesystem.read_file(path)

          File.rm!(tmp_path)
          assert exit_code == 0
          assert data == text

        {:error, e} ->
          IO.inspect("Got error while getting path #{e}")
          assert false
      end
    end)
  end
end
