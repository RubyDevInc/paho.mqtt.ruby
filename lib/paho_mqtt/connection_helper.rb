module PahoMqtt
  class ConnectionHelper

    def initialize
      @cs = MQTT_CS_DISCONNECT
    end
    
    def do_connect(reconnection=false)
      # Waiting a Connack packet for "ack_timeout" second from the remote
      connect_timeout = Time.now + @ack_timeout
      while (Time.now <= connect_timeout) && (!is_connected) do
        @cs ||= @handler.receive_packet(@socket)
        sleep 0.0001
      end
      @last_ping_resp = Time.now
      unless is_connected?
        @logger.warn("Connection failed. Couldn't recieve a Connack packet from: #{@host}, socket is \"#{@socket}\".") if @logger.is_a?(Logger)
        raise Exception.new("Connection failed. Check log for more details.") unless reconnection
      else
        config_subscription if reconnection
      end
      @cs
    end

    def is_connected?
      @cs == MQTT_CS_CONNECTED
    end
    
    def do_disconnect(publisher, explicit, mqtt_thread)
      @logger.debug("Disconnecting from #{@host}") if @logger.is_a?(Logger)
      if explicit
        @sender.flush_waiting_packet
        @sender.send_disconnect
        mqtt_thread.kill if mqtt_thread && mqtt_thread.alive?
        publisher.flush_publisher
      end
      @socket.close unless @socket.nil? || @socket.closed?
      @socket = nil
    end
    
    def setup_connection()
      clean_start
      config_socket
      unless @socket.nil?
        @sender = PahoMqtt::Sender.new(@socket)
        @handler = PahoMqtt::Handler.new
      end
    end
    
    def config_socket(ssl_context=nil)
      @logger.debug("Atempt to connect to host: #{@host}") if @logger.is_a?(Logger)
      begin
        tcp_socket = TCPSocket.new(@host, @port)
      rescue ::Exception => exp
        @logger.warn("Could not open a socket with #{@host} on port #{@port}") if @logger.is_a?(Logger)
      end
      
      if @ssl
        unless @ssl_context.nil?
          @socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, ssl_context)
          @socket.sync_close = true
          @socket.connect
        else
          @logger.error("The ssl context was found as nil while the socket's opening.") if @logger.is_a?(Logger)
          raise Exception
        end
      else
        @socket = tcp_socket
      end
      @socket
    end
    
    def clean_start
      if @host.nil? || @host == ""
        @logger.error("The host was found as nil while the connection setup.") if @logger.is_a?(Logger)
        raise ArgumentError
      end
      if @port.to_i <= 0
        @logger.error("The port value is invalid (<= 0). Could not setup the connection.") if @logger.is_a?(Logger)
        raise ArgumentError
      end
      unless @socket.nil?
        @socket.close unless @socket.closed?
        @socket = nil
      end
    end
    
    def send_connect(mqtt_version, clean_session, keep_alive, client_id, username, password, will_topic, will_payload,will_qos, will_retain)
      packet = PahoMqtt::Packet::Connect.new(
        :version => mqtt_version,
        :clean_session => clean_session,
        :keep_alive => keep_alive,
        :client_id => client_id,
        :username => username,
        :password => password,
        :will_topic => will_topic,
        :will_payload => will_payload,
        :will_qos => will_qos,
        :will_retain => will_retain
      )
      @sender.sending(packet)
      MQTT_ERR_SUCCESS
    end

    def send_disconnect
      packet = PahoMqtt::Packet::Disconnect.new
      @sender.sending(packet)
      MQTT_ERR_SUCCESS
    end

    def send_pingreq
      packet = PahoMqtt::Packet::Pingreq.new
      @sender.sending(packet)
      MQTT_ERR_SUCCESS
    end
 
    def check_keep_alive(persistent?)
      now = Time.now
      timeout_req = (@sender.last_ping_req + (@keep_alive * 0.7).ceil)
 
      if timeout_req <= now && persistent?
        @logger.debug("Checking if server is still alive.") if @logger.is_a?(Logger)
        @sender.send_pingreq
      end
      
      timeout_resp = @last_ping_resp + (@keep_alive * 1.1).ceil
      if timeout_resp <= now
        @logger.debug("No activity period over timeout, disconnecting from #{@host}") if @logger.is_a?(Logger)
        @cs = MQTT_CS_DISCONNECT
      end
      @cs
    end
  end
end
