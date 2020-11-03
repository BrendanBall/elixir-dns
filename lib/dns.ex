defmodule DNS do
  @doc """
  Resolves the answer for a DNS query

  Example:

      iex> DNS.resolve("tungdao.com")                      # {:ok, [{1, 1, 1, 1}]}
      iex> DNS.resolve("tungdao.com", :txt)                # {:ok, [['v=spf1 a mx ~all']]}
      iex> DNS.resolve("tungdao.com", :a, {"8.8.8.8", 53}) # {:ok, [{1, 1, 1, 1}]}
  """
  @spec resolve(String.t, atom, {String.t, :inet.port}) :: {atom, :inet.ip} | {atom, list} | {atom, atom}
  def resolve(domain, type \\ :a, dns_server \\ {"8.8.8.8", 53}, proto \\ :udp) do
    case query(domain, type, dns_server, proto).anlist do
      answers when is_list(answers) and length(answers) > 0 ->
        data =
          answers
          |> Enum.map(& &1.data)
          |> Enum.reject(&is_nil/1)

        {:ok, data}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Queries the DNS server and returns the result

  Examples:

      iex> DNS.query("tungdao.com")                                    # <= Queries for A records
      iex> DNS.query("tungdao.com", :mx)                               # <= Queries for the MX records
      iex> DNS.query("tungdao.com", :a, { "208.67.220.220", 53})       # <= Queries for A records, using OpenDNS
      iex> DNS.query("tungdao.com", :a, { "208.67.220.220", 53}, :tcp) # <= Queries for A records, using OpenDNS, with TCP
  """
  @spec query(String.t, atom, {String.t, :inet.port}, :tcp | :udp) :: DNS.Record.t
  def query(domain, type \\ :a, dns_server \\ {"8.8.8.8", 53}, proto \\ :udp) do
    record = %DNS.Record{
      header: %DNS.Header{rd: true},
      qdlist: [%DNS.Query{domain: to_charlist(domain), type: type, class: :in}]
    }

    encoded_record = DNS.Record.encode(record)

    response_data =
      case proto do
        :udp ->
          client = Socket.UDP.open!(0)

          Socket.Datagram.send!(client, encoded_record, dns_server)

          {data, _server} = Socket.Datagram.recv!(client, timeout: 5_000)

          :gen_udp.close(client)

          data

        :tcp ->
          socket = Socket.TCP.connect! dns_server, timeout: 5_000

          # Add our 2 byte length header (big endian) per https://tools.ietf.org/html/rfc1035#section-4.2.2
          tcp_packet = << byte_size(encoded_record) :: 16 >> <> encoded_record

          :ok = Socket.Stream.send(socket, tcp_packet)

          # Parse out our length header, and only return that number of bytes to be RFC compliant
          << recv_size :: integer-16,
             data      :: binary - size(recv_size)
             >> = Socket.Stream.recv!(socket)

          Socket.Stream.close! socket

          data
      end

    DNS.Record.decode(response_data)
  end
end
