module PahoMqtt
  class Handler

    attr_reader :registered_callback
    attr_accessor :last_ping_resp
    
    def initialize
      @registered_callback = []
      @last_ping_resp = -1
      @publisher = nil
      @subscriber = nil
    end

    def config_pubsub(publisher, subscriber)
      @publisher = publisher
      @subscriber = subscriber
    end

    def socket=(socket)
      @socket = socket
    end

    def receive_packet
      result = IO.select([@socket], [], [], SELECT_TIMEOUT) unless @socket.nil? || @socket.closed?
      unless result.nil?
        packet = PahoMqtt::Packet::Base.read(@socket)
        unless packet.nil?
          if packet.is_a?(PahoMqtt::Packet::Connack)
            @last_ping_resp = Time.now
            cs = handle_connack(packet)
          else
            handle_packet(packet)
            @last_ping_resp = Time.now
          end          
        end
      end
    end

    def handle_packet(packet)
      @logger.info("New packet #{packet.class} recieved.") if PahoMqtt.logger?
      if packet.class == PahoMqtt::Packet::Suback
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
        @logger.error("The packets header is invalid for packet: #{packet}") if PahoMqtt.logger?
        raise PacketException
      end
    end

    def register_topic_callback(topic, callback, &block)
      if topic.nil?
        @logger.error("The topics where the callback is trying to be registered have been found nil.") if PahoMqtt.logger?
        raise ArgumentError
      end
      clear_topic_callback(topic)
      if block_given?
        @registered_callback.push([topic, block])
      elsif !(callback.nil?) && callback.is_a?(Proc)
        @registered_callback.push([topic, callback])
      end
      MQTT_ERR_SUCCESS
    end

    def clear_topic_callback(topic)
      if topic.nil?
        @logger.error("The topics where the callback is trying to be unregistered have been found nil.") if PahoMqtt.logger?
        raise ArgumentError
      end
      @registered_callback.delete_if {|pair| pair.first == topic}
      MQTT_ERR_SUCCESS
    end

    def handle_connack(packet)
      if packet.return_code == 0x00
        @logger.debug("Connack receive and connection accepted.") if PahoMqtt.logger?
        if @clean_session && !packet.session_present
          @logger.debug("New session created for the client") if PahoMqtt.logger?
        elsif !@clean_session && !packet.session_present
          @logger.debug("No previous session found by server, starting a new one.") if PahoMqtt.logger?
        elsif !@clean_session && packet.session_present
          @logger.debug("Previous session restored by the server.") if PahoMqtt.logger?
        end
      else
        handle_connack_error(packet.return_code)
      end
      @on_connack.call(packet) unless @on_connack.nil?
      MQTT_CS_CONNECTED
    end

    def handle_pingresp
      @last_ping_resp = Time.now
    end

    def handle_suback(packet)
      max_qos = packet.return_codes
      id = packet.id
      topics = []
      if @subscriber.add_subscription(max_qos, id, topics) == MQTT_ERR_SUCCESS
        @on_suback.call(topics) unless @on_suback.nil?
      end
    end

    def handle_unsuback(packet)
      id = packet.id
      topics = []
      if @subscriber.remove_subscription(id, topics) == MQTT_ERR_SUCCESS
        @on_unsuback.call(topics) unless @on_unsuback.nil?
      end
    end

    def handle_publish(packet)
      id = packet.id
      qos = packet.qos
      if @publisher.do_publish(qos, id) == MQTT_ERR_SUCCESS
        @on_message.call(packet) unless @on_message.nil?
        @registered_callback.assoc(packet.topic).last.call(packet) if @registered_callback.any? { |pair| pair.first == packet.topic}
      end
    end

    def handle_puback(packet)
      id = packet.id
      if @publisher.do_puback(id) == MQTT_ERR_SUCCESS
        @on_puback.call(packet) unless @on_puback.nil?
      end
    end

    def handle_pubrec(packet)
      id = packet.id
      if @publisher.do_pubrec(id) == MQTT_ERR_SUCCESS      
        @on_pubrec.call(packet) unless @on_pubrec.nil?
      end
    end

    def handle_pubrel(packet)
      id = packet.id
      if @publisher.do_pubrel(id) == MQTT_ERR_SUCCESS
        @on_pubrel.call(packet) unless @on_pubrel.nil?
      end
    end

    def handle_pubcomp(packet)
      id = packet.id
      if @publisher.do_pubcomp(id) == MQTT_ERR_SUCCESS
        @on_pubcomp.call(packet) unless @on_pubcomp.nil?
      end
    end

    def handle_connack_error(return_code)
      case return_code
      when 0x01
        @logger.debug("Unable to connect to the server with the version #{@mqtt_version}, trying 3.1") if PahoMqtt.logger?
        if @mqtt_version != "3.1"
          @mqtt_version = "3.1"
          connect(@host, @port, @keep_alive)
        end
      when 0x02
        @logger.warn("Client Identifier is correct but not allowed by remote server.") if PahoMqtt.logger?
        MQTT_CS_DISCONNECTD
      when 0x03
        @logger.warn("Connection established but MQTT service unvailable on remote server.") if PahoMqtt.logger?
        MQTT_CS_DISCONNECTD
      when 0x04
        @logger.warn("User name or user password is malformed.") if PahoMqtt.logger?
        MQTT_CS_DISCONNECTD
      when 0x05
        @logger.warn("Client is not authorized to connect to the server.") if PahoMqtt.logger?
        MQTT_CS_DISCONNECTD
      end
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

    def on_connack=(callback)
      @on_connack = callback if callback.is_a?(Proc)
    end

    def on_suback=(callback)
      @on_suback = callback if callback.is_a?(Proc)
    end

    def on_unsuback=(callback)
      @on_unsuback = callback if callback.is_a?(Proc)
    end

    def on_puback=(callback)
      @on_puback = callback if callback.is_a?(Proc)
    end

    def on_pubrec=(callback)
      @on_pubrec = callback if callback.is_a?(Proc)
    end

    def on_pubrel=(callback)
      @on_pubrel = callback if callback.is_a?(Proc)
    end

    def on_pubcomp=(callback)
      @on_pubcomp = callback if callback.is_a?(Proc)
    end

    def on_message=(callback)
      @on_message = callback if callback.is_a?(Proc)
    end
  end
end
