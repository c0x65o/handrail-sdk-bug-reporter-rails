require "net/http"
require "socket"

# Fail before an external connection, and remember attempts even if rescued.
module NoNetwork
  ATTEMPTS = []

  def self.reject(operation)
    ATTEMPTS << operation
    raise "Network access forbidden in scaffold smoke tests: #{operation}"
  end

  module HTTP
    def request(*args)
      NoNetwork.reject("Net::HTTP#request")
    end
  end

  module TCP
    def new(*args)
      NoNetwork.reject("TCPSocket.new")
    end

    def open(*args)
      NoNetwork.reject("TCPSocket.open")
    end
  end

  module SocketConnection
    def connect(*args)
      NoNetwork.reject("Socket#connect")
    end

    def connect_nonblock(*args)
      NoNetwork.reject("Socket#connect_nonblock")
    end
  end

  module SocketTCP
    def tcp(*args)
      NoNetwork.reject("Socket.tcp")
    end
  end
end

Net::HTTP.prepend(NoNetwork::HTTP)
TCPSocket.singleton_class.prepend(NoNetwork::TCP)
Socket.prepend(NoNetwork::SocketConnection)
Socket.singleton_class.prepend(NoNetwork::SocketTCP)

at_exit do
  raise "Unexpected network attempts: #{NoNetwork::ATTEMPTS.inspect}" unless NoNetwork::ATTEMPTS.empty?
end
