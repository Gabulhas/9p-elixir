defmodule P9server do
  alias Types.Messages

  def start(port \\ 4000) do
    {:ok, supervisor} = Task.Supervisor.start_link(name: TCPSupervisor)

    tcp_options = [:binary, packet: :raw, active: false, reuseaddr: true]
    {:ok, listen_socket} = :gen_tcp.listen(port, tcp_options)

    IO.puts("Supervised server listening on #{port}...")
    accept_loop(supervisor, listen_socket)
  end

  defp accept_loop(supervisor, listen_socket) do
    {:ok, client_socket} = :gen_tcp.accept(listen_socket)

    Task.Supervisor.start_child(supervisor, fn -> serve(client_socket) end)

    accept_loop(supervisor, listen_socket)
  end

  defp receive_message(socket) do
    with {:ok, size_bytes} <- :gen_tcp.recv(socket, 4),
         <<total_size::little-integer-size(32)>> = size_bytes,
         {:ok, type_bytes} <- :gen_tcp.recv(socket, 1),
         {:ok, tag_bytes} <- :gen_tcp.recv(socket, 2),
         bytes_left = total_size - 7,
         {:ok, payload} <- :gen_tcp.recv(socket, bytes_left) do
      <<size::little-integer-size(32)>> = size_bytes
      <<msg_type::little-integer-size(8)>> = type_bytes
      <<tag::little-integer-size(16)>> = tag_bytes

      result = %Messages{
        size: size,
        type: msg_type,
        tag: tag,
        payload: payload
      }

      {:ok, result}
    else
      {:error, :closed} ->
        IO.puts("Client disconnected halfway through")
        {:error, :closed}

      {:error, reason} ->
        IO.puts("Failed with reason: #{reason}")
        {:error, reason}
    end
  end

  defp serve(socket) do
    {:ok, fid_store} = Agent.start_link(fn -> %{} end)
    {:ok, file_store} = Agent.start_link(fn -> %{} end)
    serve_loop(socket, fid_store, file_store)
  end

  defp serve_loop(socket, fid_store, file_store) do
    case receive_message(socket) do
      {:ok, received_message} ->
        parsed_message = Protocolparser.parse_payload(received_message)
        IO.inspect(parsed_message)

        case response(received_message, parsed_message, fid_store, file_store) do
          data when is_binary(data) or is_list(data) ->
            :gen_tcp.send(socket, data)

          other ->
            IO.inspect(other, label: "INVALID RESPONSE FORMAT FROM HANDLER")
        end

        serve_loop(socket, fid_store, file_store)

      {:error, reason} ->
        IO.inspect(reason)
    end
  end

  defp response(message, parsed, fid_store, file_store) do
    %Messages{
      tag: tag
    } = message

    Fakefilesystem.MessageHandler.handle(parsed, tag, fid_store, file_store)
  end
end
