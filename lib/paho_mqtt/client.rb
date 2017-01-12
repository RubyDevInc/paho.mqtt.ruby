require 'openssl'
require 'socket'
require 'logger'

module PahoMqtt
  class Client    
    # Log file
    attr_accessor :logger
    
    # Connection related attributes:
    attr_accessor :host
    attr_accessor :port
    attr_accessor :mqtt_version
    attr_accessor :clean_session
    attr_accessor :persistent
    attr_accessor :client_id
    attr_accessor :username
    attr_accessor :password
    attr_accessor :ssl
    
    # Last will attributes:
    attr_accessor :will_topic
    attr_accessor :will_payload
    attr_accessor :will_qos
    attr_accessor :will_retain

    # Timeout attributes:
    attr_accessor :keep_alive
    attr_accessor :ack_timeout

    #Callback attributes
    attr_accessor :on_message
    attr_accessor :on_connack
    attr_accessor :on_suback
    attr_accessor :on_unsuback
    attr_accessor :on_puback
    attr_accessor :on_pubrel
    attr_accessor :on_pubrec
    attr_accessor :on_pubcomp

    #Read Only attribute
    attr_reader :registered_callback
    attr_reader :subscribed_topics
    attr_reader :connection_state

    ATTR_DEFAULTS = {
      :logger => nil,
      :host => "",
      :port => nil,
      :mqtt_version => '3.1.1',
      :clean_session => true,
      :persistent => false,
      :client_id => nil,
      :username => nil,
      :password => nil,
      :ssl => false,
      :will_topic => nil,
      :will_payload => nil,
      :will_qos => 0,
      :will_retain => false,
      :keep_alive => 60,
      :ack_timeout => 5,
      :on_connack => nil,
      :on_suback => nil,
      :on_unsuback => nil,
      :on_puback => nil,
      :on_pubrel => nil,
      :on_pubrec => nil,
      :on_pubcomp => nil,
      :on_message => nil,
    }
    
    def initialize(*args)
      if args.last.is_a?(Hash)
        attr = args.pop
      else
        attr = {}
      end

      ATTR_DEFAULTS.merge(attr).each_pair do |k,v|
        self.send("#{k}=", v)
      end

      if @port.nil?
        @port
        if @ssl
          @port = PahoMqtt::DEFAULT_SSL_PORT
        else
          @port = PahoMqtt::DEFAULT_PORT
        end
      end

      if  @client_id.nil? || @client_id == ""
        @client_id = generate_client_id
      end

      @last_ping_req = Time.now
      @last_ping_resp = Time.now
      @last_packet_id = 0
      @blocking = false
      @socket = nil
      @ssl_context = nil
      @writing_mutex = Mutex.new
      @writing_queue = []
      @connection_state = MQTT_CS_DISCONNECT
      @connection_state_mutex = Mutex.new
      @subscribed_mutex = Mutex.new
      @subscribed_topics = []
      @registered_callback = []
      @waiting_suback = []
      @suback_mutex = Mutex.new
      @waiting_unsuback = []
      @unsuback_mutex = Mutex.new
      @mqtt_thread = nil
      @reconnect_thread = nil

      @puback_mutex = Mutex.new
      @pubrec_mutex = Mutex.new
      @pubrel_mutex = Mutex.new
      @pubcomp_mutex = Mutex.new
      @waiting_puback = []
      @waiting_pubrec = []
      @waiting_pubrel = []
      @waiting_pubcomp = []
    end

    def generate_client_id(prefix='paho_ruby', lenght=16)
      charset = Array('A'..'Z') + Array('a'..'z') + Array('0'..'9')
      @client_id = prefix << Array.new(lenght) { charset.sample }.join
    end

    def ssl_context
      @ssl_context ||= OpenSSL::SSL::SSLContext.new
    end

    def config_ssl_context(cert_path, key_path, ca_path=nil)
      @ssl ||= true
      @ssl_context = ssl_context
      self.cert = cert_path
      self.key = key_path
      self.root_ca = ca_path
    end
    
    def config_will(topic, payload="", retain=false, qos=0)
      @will_topic = topic
      @will_payload = payload
      @will_retain = retain
      @will_qos = qos
    end

    def connect(host=@host, port=@port, keep_alive=@keep_alive, persistent=@persistent, blocking=@blocking)
      @persistent = persistent
      @blocking = blocking
      @host = host
      @port = port.to_i
      @keep_alive = keep_alive
      @connection_state_mutex.synchronize {
        @connection_state = MQTT_CS_NEW
      }
      setup_connection
      connect_async(host, port, keep_alive) unless @blocking
    end

    def connect_async(host, port=1883, keep_alive)
      @mqtt_thread = Thread.new do
        @reconnect_thread.kill unless @reconnect_thread.nil? || !@reconnect_thread.alive?
        while @connection_state == MQTT_CS_CONNECTED do
          mqtt_loop
        end
      end
    end

    def loop_write(max_packet=MAX_WRITING)
      @writing_mutex.synchronize {
        cnt = 0
        while !@writing_queue.empty? && cnt < max_packet do
          send_packet(@writing_queue.shift)
          cnt += 1
        end
      }
    end

    def loop_read(max_packet=MAX_READ)
      max_packet.times do
        receive_packet
      end
    end

    def mqtt_loop
      loop_read
      loop_write
      loop_misc
      sleep LOOP_TEMPO
    end

    def loop_misc
      check_keep_alive
      check_ack_alive(@waiting_puback, @puback_mutex, MAX_PUBACK)
      check_ack_alive(@waiting_pubrec, @pubrec_mutex, MAX_PUBREC)
      check_ack_alive(@waiting_pubrel, @pubrel_mutex, MAX_PUBREL)
      check_ack_alive(@waiting_pubcomp, @pubcomp_mutex, MAX_PUBCOMP)
      check_ack_alive(@waiting_suback, @suback_mutex, @waiting_suback.length)
      check_ack_alive(@waiting_unsuback, @unsuback_mutex, @waiting_unsuback.length)
    end

    def reconnect(retry_time=RECONNECT_RETRY_TIME, retry_tempo=RECONNECT_RETRY_TEMPO)
      @reconnect_thread = Thread.new do
        retry_time.times do
          @logger.debug("New reconnect atempt...") if @logger.is_a?(Logger)
          connect
          if @connection_state == MQTT_CS_CONNECTED
            break
          else
            sleep retry_tempo
          end
        end
        if @connection_state != MQTT_CS_CONNECTED
          @logger.error("Reconnection atempt counter is over.(#{RECONNECT_RETRY_TIME} times)") if @logger.is_a?(Logger)
          disconnect(false)
          exit
        end
      end
    end

    def disconnect(explicit=true)
      @logger.debug("Disconnecting from #{@host}") if @logger.is_a?(Logger)

      if explicit
        send_disconnect
        @mqtt_thread.kill if @mqtt_thread && @mqtt_thread.alive?
        @mqtt_thread.kill if @mqtt_thread.alive?
        @last_packet_id = 0

        @writing_mutex.synchronize {
          @writing_queue = []
        }

        @puback_mutex.synchronize {
          @waiting_puback = []
        }

        @pubrec_mutex.synchronize {
          @waiting_pubrec = []
        }

        @pubrel_mutex.synchronize {
          @waiting_pubrel = []
        }

        @pubcomp_mutex.synchronize {
          @waiting_pubcomp = []
        }
      end

      @socket.close unless @socket.nil?
      @socket = nil

      @connection_state_mutex.synchronize {
        @connection_state = MQTT_CS_DISCONNECT
      }
      MQTT_ERR_SUCCESS
    end

    def publish(topic, payload="", retain=false, qos=0)
      if topic == "" || !topic.is_a?(String)
        @logger.error("Publish topics is invalid, not a string or empty.") if @logger.is_a?(Logger)
        raise ParameterException
      end
      send_publish(topic, payload, retain, qos)
    end

    def subscribe(*topics)
      unless topics.length == 0
        send_subscribe(topics)
      else
        @logger.error("Subscribe topics need one topic or a list of topics.") if @logger.is_a?(Logger)
        disconnect(false)
        raise ProtocolViolation
      end
    end

    def unsubscribe(*topics)
      unless topics.length == 0
        send_unsubscribe(topics)
      else
        @logger.error("Unsubscribe need at least one topics.") if @logger.is_a?(Logger)
        disconnect(false)
        raise ProtocolViolation
      end
    end

    def ping_host
      send_pingreq
    end

    def add_topic_callback(topic, callback=nil, &block)
      if topic.nil?
        @logger.error("The topics where the callback is trying to be registered have been found nil.") if @logger.is_a?(Logger)
        raise ParameterException
      end
      remove_topic_callback(topic)

      if block_given?
        @registered_callback.push([topic, block])
      elsif !(callback.nil?) && callback.class == Proc
        @registered_callback.push([topic, callback])
      end
      MQTT_ERR_SUCCESS
    end

    def remove_topic_callback(topic)
      if topic.nil?
        @logger.error("The topics where the callback is trying to be unregistered have been found nil.") if @logger.is_a?(Logger)
        raise ParameterException
      end
      @registered_callback.delete_if {|pair| pair.first == topic}
      MQTT_ERR_SUCCESS
    end
    
    def on_connack(&block)
      @on_connack = block if block_given?
      @on_connack
    end

    def on_suback(&block)
      @on_suback = block if block_given?
      @on_suback
    end

    def on_unsuback(&block)
      @on_unsuback = block if block_given?
      @on_unsuback
    end

    def on_puback(&block)
      @on_puback = block if block_given?
      @on_puback
    end

    def on_pubrec(&block)
      @on_pubrec = block if block_given?
      @on_pubrec
    end

    def on_pubrel(&block)
      @on_pubrel = block if block_given?
      @on_pubrel
    end

    def on_pubcomp(&block)
      @on_pubcomp = block if block_given?
      @on_pubcomp
    end

    def on_message(&block)
      @on_message = block if block_given?
      @on_message
    end

    private

    def next_packet_id
      @last_packet_id = ( @last_packet_id || 0 ).next
    end

    def config_subscription
      unless @subscribed_topics == []
        new_id = next_packet_id
        packet = PahoMqtt::Packet::Subscribe.new(
          :id => new_id,
          :topics => @subscribed_topics
        )
        @subscribed_mutex.synchronize {
          @subscribed_topics = []
        }
        @suback_mutex.synchronize {
          @waiting_suback.push({ :id => new_id, :packet => packet, :timestamp => Time.now })
        }
        send_packet(packet)
      end
      MQTT_ERR_SUCCESS
    end

    def config_all_message_queue
      config_message_queue(@waiting_puback, @puback_mutex, MAX_PUBACK)
      config_message_queue(@waiting_pubrec, @pubrec_mutex, MAX_PUBREC)
      config_message_queue(@waiting_pubrel, @pubrel_mutex, MAX_PUBREL)
      config_message_queue(@waiting_pubcomp, @pubcomp_mutex, MAX_PUBCOMP)
    end

    def config_message_queue(queue, mutex, max_packet)
      mutex.synchronize {
        cnt = 0 
        queue.each do |pck|
          pck[:packet].dup ||= true
          if cnt <= max_packet
            append_to_writing(pck[:packet])
            cnt += 1
          end
        end
      }
    end

    def config_socket
      unless @socket.nil?
        @socket.close
        @socket = nil
      end

      unless @host.nil? || @port < 0
        begin
          tcp_socket = TCPSocket.new(@host, @port)
        rescue ::Exception => exp
          @logger.warn("Could not open a socket with #{@host} on port #{@port}") if @logger.is_a?(Logger)
        end
      end

      if @ssl
        unless @ssl_context.nil?
          @socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, @ssl_context)
          @socket.sync_close = true
          @socket.connect
        else
          @logger.error("The ssl context was found as nil while the socket's opening.") if @logger.is_a?(Logger)
          raise Exception
        end
      else
        @socket = tcp_socket
      end
    end

    def cert=(cert_path)
      ssl_context.cert = OpenSSL::X509::Certificate.new(File.read(cert_path))
    end

    def key=(key_path)
      ssl_context.key = OpenSSL::PKey::RSA.new(File.read(key_path))
    end

    def root_ca=(ca_path)
      ssl_context.ca_file = ca_path
      unless @ca_path.nil?
        ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER
      end
    end

    def setup_connection
      @mqtt_thread.kill unless @mqtt_thread.nil? 
      if @host.nil? || @host == ""
        @logger.error("The host was found as nil while the connection setup.") if @logger.is_a?(Logger)
        raise ParameterException
      end

      if @port.to_i <= 0
        @logger.error("The port value is invalid (<= 0). Could not setup the connection.") if @logger.is_a?(Logger)
        raise ParameterException
      end

       @socket.close unless @socket.nil?
       @socket = nil

       @last_ping_req = Time.now
       @last_ping_resp = Time.now

       @logger.debug("Atempt to connect to host: #{@host}") if @logger.is_a?(Logger)
       config_socket

       unless @socket.nil?
         send_connect

         # Waiting a Connack packet for "ack_timeout" second from the remote
         connect_timeout = Time.now + @ack_timeout
         while (Time.now <= connect_timeout) && (@connection_state != MQTT_CS_CONNECTED) do
           receive_packet
           sleep 0.0001
         end
       end

       if @connection_state != MQTT_CS_CONNECTED
         @logger.warn("Connection failed. Couldn't recieve a Connack packet from: #{@host}, socket is \"#{@socket}\".") if @logger.is_a?(Logger)
         unless Thread.current == @reconnect_thread
           raise Exception.new("Connection failed. Check log for more details.")
         end
       else
         config_subscription if Thread.current == @reconnect_thread
       end
    end

    def check_keep_alive
      if @keep_alive >= 0 && @connection_state == MQTT_CS_CONNECTED
        now = Time.now
        timeout_req = (@last_ping_req + (@keep_alive * 0.7).ceil)

        if timeout_req <= now && @persistent
          send_pingreq
          @last_ping_req = now
        end

        timeout_resp = @last_ping_resp + (@keep_alive * 1.1).ceil
        if timeout_resp <= now
          @logger.debug("No activity period over timeout, disconnecting from #{@host}") if @logger.is_a?(Logger)
          disconnect(false)
          reconnect if @persistent
        end
      end
    end

    def check_ack_alive(queue, mutex, max_packet)
      mutex.synchronize {
        now = Time.now
        cnt = 0
        queue.each do |pck|
          if now >= pck[:timestamp] + @ack_timeout
            pck[:packet].dup ||= true unless pck[:packet].class == PahoMqtt::Packet::Subscribe || pck[:packet].class == PahoMqtt::Packet::Unsubscribe
            unless cnt > max_packet
              append_to_writing(pck[:packet]) 
              pck[:timestamp] = now
              cnt += 1
            end
          end
        end
      }
    end

    def receive_packet
      begin
        result = IO.select([@socket], [], [], SELECT_TIMEOUT) unless @socket.nil?
        unless result.nil?
          packet = PahoMqtt::Packet.read(@socket)
          unless packet.nil?
            handle_packet packet
            @last_ping_resp = Time.now
          end
        end
      rescue ::Exception => exp
        disconnect(false)
        if @persistent
          reconnect
        else
          @logger.error("The packet reading have failed.") if @logger.is_a?(Logger)
          raise(exp)
        end
      end
    end

    def handle_packet(packet)      
      @logger.info("New packet #{packet.class} recieved.") if @logger.is_a?(Logger)
      if packet.class == PahoMqtt::Packet::Connack
        handle_connack(packet)
      elsif packet.class == PahoMqtt::Packet::Suback
        handle_suback(packet)
      elsif packet.class == PahoMqtt::Packet::Unsuback
        handle_unsuback(packet)
      elsif packet.class == PahoMqtt::Packet::Publish
        handle_publish(packet)
      elsif packet.class == PahoMqtt::Packet::Puback
        handle_puback(packet)
      elsif packet.class == PahoMqtt::Packet::Pubrec
        handle_pubrec(packet)
      elsif packet.class == PahoMqtt::Packet::Pubrel
        handle_pubrel(packet)
      elsif packet.class == PahoMqtt::Packet::Pubcomp
        handle_pubcomp(packet)
      elsif packet.class == PahoMqtt::Packet::Pingresp
        handle_pingresp
      else
        @logger.error("The packets header is invalid for packet: #{packet}") if @logger.is_a?(Logger)
        raise PacketException
      end
    end

    def handle_connack(packet)
      if packet.return_code == 0x00
        @logger.debug("Connack receive and connection accepted.") if @logger.is_a?(Logger)
        if @clean_session && !packet.session_present
          @logger.debug("New session created for the client") if @logger.is_a?(Logger)
        elsif !@clean_session && !packet.session_present
          @logger.debug("No previous session found by server, starting a new one.") if @logger.is_a?(Logger)
        elsif !@clean_session && packet.session_present
          @logger.debug("Previous session restored by the server.") if @logger.is_a?(Logger)
        end
        @connection_state_mutex.synchronize{
          @connection_state = MQTT_CS_CONNECTED
        }
      else
        disconnect(false)
        handle_connack_error(packet.return_code)
      end
      config_all_message_queue
      @writing_mutex.synchronize {
        @writing_queue.each do |m|
          send_packet(m)
        end
      }
      @on_connack.call(packet) unless @on_connack.nil?
    end

    def handle_pingresp
      @last_ping_resp = Time.now
    end

    def handle_suback(packet)
      adjust_qos = []
      max_qos = packet.return_codes
      @suback_mutex.synchronize {
        adjust_qos, @waiting_suback = @waiting_suback.partition { |pck| pck[:id] == packet.id }
      }
      if adjust_qos.length == 1
        adjust_qos = adjust_qos.first[:packet].topics
        adjust_qos.each do |t|
          if [0, 1, 2].include?(max_qos[0])
            t[1] = max_qos.shift
          elsif max_qos[0] == 128
            adjust_qos.delete(t)
          else
            @logger.error("The qos value is invalid in subscribe.") if @logger.is_a?(Logger)
            raise PacketException
          end
        end
      else
        @logger.error("The packet id is invalid, already used.") if @logger.is_a?(Logger)
        raise PacketException
      end
      @subscribed_mutex.synchronize {
        @subscribed_topics.concat(adjust_qos)
      }
      @on_suback.call(packet) unless @on_suback.nil?
    end

    def handle_unsuback(packet)
      to_unsub = nil
      @unsuback_mutex.synchronize {
        to_unsub, @waiting_unsuback = @waiting_unsuback.partition { |pck| pck[:id] == packet.id }
      }
      
      if to_unsub.length == 1
        to_unsub = to_unsub.first[:packet].topics
      else
        @logger.error("The packet id is invalid, already used.") if @logger.is_a?(Logger)
        raise PacketException
      end

      @subscribed_mutex.synchronize {
        to_unsub.each do |filter|
          @subscribed_topics.delete_if { |topic| match_filter(topic.first, filter) }
        end
      }
      @on_unsuback.call(packet) unless @on_unsuback.nil?
    end

    def handle_publish(packet)
      case packet.qos
      when 0
      when 1
        send_puback(packet.id)
      when 2
        send_pubrec(packet.id)
      else
        @logger.error("The packet qos value is invalid in publish.") if @logger.is_a?(Logger)
        raise PacketException
      end

      @on_message.call(packet) unless @on_message.nil?
      @registered_callback.assoc(packet.topic).last.call(packet) if @registered_callback.any? { |pair| pair.first == packet.topic}
    end

    def handle_puback(packet)
      @puback_mutex.synchronize{
        @waiting_puback.delete_if { |pck| pck[:id] == packet.id }
      }
      @on_puback.call(packet) unless @on_puback.nil?
    end

    def handle_pubrec(packet)
      @pubrec_mutex.synchronize {
        @waiting_pubrec.delete_if { |pck| pck[:id] == packet.id }
      }
      send_pubrel(packet.id)
      @on_pubrec.call(packet) unless @on_pubrec.nil?
    end

    def handle_pubrel(packet)
      @pubrel_mutex.synchronize {
        @waiting_pubrel.delete_if { |pck| pck[:id] == packet.id }
      }
      send_pubcomp(packet.id)
      @on_pubrel.call(packet) unless @on_pubrel.nil?
    end

    def handle_pubcomp(packet)
      @pubcomp_mutex.synchronize {
        @waiting_pubcomp.delete_if { |pck| pck[:id] == packet.id }
      }
      @on_pubcomp.call(packet) unless @on_pubcomp.nil?
    end
    
    def handle_connack_error(return_code)
      case return_code
      when 0x01
        @logger.debug("Unable to connect to the server with the version #{@mqtt_version}, trying 3.1") if @logger.is_a?(Logger)
        if @mqtt_version != "3.1"
          @mqtt_version = "3.1"
          connect(@host, @port, @keep_alive)
        end
      when 0x02
        @logger.warn("Client Identifier is correct but not allowed by remote server.") if @logger.is_a?(Logger)
        MQTT_ERR_FAIL
      when 0x03
        @logger.warn("Connection established but MQTT service unvailable on remote server.") if @logger.is_a?(Logger)
        MQTT_ERR_FAIL
      when 0x04
        @logger.warn("User name or user password is malformed.") if @logger.is_a?(Logger)
        MQTT_ERR_FAIL
      when 0x05
        @logger.warn("Client is not authorized to connect to the server.") if @logger.is_a?(Logger)
        MQTT_ERR_FAIL
      end
    end
    
    def send_packet(packet)
      unless @socket.nil? || @socket.closed?
        @socket.write(packet.to_s)
        @logger.info("A packet #{packet.class} have been sent.") if @logger.is_a?(Logger)
        @last_ping_req = Time.now
        MQTT_ERR_SUCCESS
      else
        @logger.error("Trying to right a packet on a nil socket.") if @logger.is_a?(Logger)
        MQTT_ERR_FAIL
      end
    end
    
    
    def append_to_writing(packet)
      @writing_mutex.synchronize {
        @writing_queue.push(packet)
      }
      MQTT_ERR_SUCCESS
    end

    def send_connect
      packet = PahoMqtt::Packet::Connect.new(
        :version => @mqtt_version,
        :clean_session => @clean_session,
        :keep_alive => @keep_alive,
        :client_id => @client_id,
        :username => @username,
        :password => @password,
        :will_topic => @will_topic,
        :will_payload => @will_payload,
        :will_qos => @will_qos,
        :will_retain => @will_retain
      )
      send_packet(packet)
      MQTT_ERR_SUCCESS
    end

    def send_disconnect
      packet = PahoMqtt::Packet::Disconnect.new
      send_packet(packet)
      MQTT_ERR_SUCCESS
    end

    def send_pingreq
      packet = PahoMqtt::Packet::Pingreq.new
      @logger.debug("Checking if server is still alive.") if @logger.is_a?(Logger)
      send_packet(packet)
      MQTT_ERR_SUCCESS
    end

    def send_subscribe(topics)
      unless topics.length == 0
        new_id = next_packet_id
        packet = PahoMqtt::Packet::Subscribe.new(
          :id => new_id,
          :topics => topics
        )        

        append_to_writing(packet)
        @suback_mutex.synchronize {
          @waiting_suback.push({ :id => new_id, :packet => packet, :timestamp => Time.now })
        }
      end        
      MQTT_ERR_SUCCESS
    end

    def send_unsubscribe(topics)
      unless topics.length == 0
        new_id = next_packet_id
        packet = PahoMqtt::Packet::Unsubscribe.new(
          :id => new_id,
          :topics => topics
        )

        append_to_writing(packet)
        @unsuback_mutex.synchronize {
          @waiting_unsuback.push({:id => new_id, :packet => packet, :timestamp => Time.now})
        }
      end
      MQTT_ERR_SUCCESS
    end

    def send_publish(topic, payload, retain, qos)
      new_id = next_packet_id
      packet = PahoMqtt::Packet::Publish.new(
        :id => new_id,
        :topic => topic,
        :payload => payload,
        :retain => retain,
        :qos => qos
      )

      append_to_writing(packet)

      case qos
      when 1
        @puback_mutex.synchronize{
          @waiting_puback.push({:id => new_id, :packet => packet, :timestamp => Time.now})
        }
      when 2
        @pubrec_mutex.synchronize{
          @waiting_pubrec.push({:id => new_id, :packet => packet, :timestamp => Time.now})
        }
      end
      MQTT_ERR_SUCCESS
    end

    def send_puback(packet_id)
      packet = PahoMqtt::Packet::Puback.new(
        :id => packet_id
      )

      append_to_writing(packet)
      MQTT_ERR_SUCCESS
    end

    def send_pubrec(packet_id)
      packet = PahoMqtt::Packet::Pubrec.new(
        :id => packet_id
      )

      append_to_writing(packet)
      
      @pubrel_mutex.synchronize{
        @waiting_pubrel.push({:id => packet_id , :packet => packet, :timestamp => Time.now})
      }
      MQTT_ERR_SUCCESS
    end
    
    def send_pubrel(packet_id)
      packet = PahoMqtt::Packet::Pubrel.new(
        :id => packet_id
      )

      append_to_writing(packet)
      
      @pubcomp_mutex.synchronize{
        @waiting_pubcomp.push({:id => packet_id, :packet => packet, :timestamp => Time.now})
      }
      MQTT_ERR_SUCCESS
    end

    def send_pubcomp(packet_id)
      packet = PahoMqtt::Packet::Pubcomp.new(
        :id => packet_id
      )

      append_to_writing(packet)
      MQTT_ERR_SUCCESS
    end

    def match_filter(topics, filters)
      if topics.is_a?(String) && filters.is_a?(String)
        topic = topics.split('/')
        filter = filters.split('/')
      else
        @logger.error("Topics and filters are not found as String while matching topics to filter.") if @logger.is_a?(Logger)
        raise ParameterException
      end
      
      rc = false
      index = 0
      
      while index < [topic.length, filter.length].max do
        if topic[index].nil? || filter[index].nil?
          break
        elsif filter[index] == '#' && index == (filter.length - 1) 
          rc = true
          break
        elsif filter[index] == topic[index] || filter[index] == '+'
          index = index + 1
        else
          break
        end
      end
      rc ||= (index == [topic.length, filter.length].max)
    end
  end
end
