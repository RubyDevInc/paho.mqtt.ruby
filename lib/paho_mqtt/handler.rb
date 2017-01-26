module PahoMqtt
  class Handler

    attr_accessor :registered_callback
    
    def initialize()
    end

    def receive_packet(socket)
      begin
        result = IO.select([socket], [], [], SELECT_TIMEOUT) unless socket.nil? || socket.closed?
        unless result.nil?
          packet = PahoMqtt::Packet::Base.read(socket)
          unless packet.nil?
            packet.is_a(PahoMqtt::Packet::Connack) ? cs = handle_connack(packet) : handle_packet(packet)
            cs
          end
        end
        raise ReadError
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
        @connection_state_mutex.synchronize{
          if accept_connection
            MQTT_CS_CONNECTED
          else
            disconnect(false)
            MQTT_CS_DISCONNECT
          end
        }
      elsif packet.class == PahoMqtt::Packet::Suback
        @handler.handle_suback(packet)
      elsif packet.class == PahoMqtt::Packet::Unsuback
        @handler.handle_unsuback(packet)
      elsif packet.class == PahoMqtt::Packet::Publish
        @handler.handle_publish(packet)
      elsif packet.class == PahoMqtt::Packet::Puback
        @handler.handle_puback(packet)
      elsif packet.class == PahoMqtt::Packet::Pubrec
        @handler.handle_pubrec(packet)
      elsif packet.class == PahoMqtt::Packet::Pubrel
        @handler.handle_pubrel(packet)
      elsif packet.class == PahoMqtt::Packet::Pubcomp
        @handler.handle_pubcomp(packet)
      elsif packet.class == PahoMqtt::Packet::Pingresp
        @handler.handle_pingresp
      else
        @logger.error("The packets header is invalid for packet: #{packet}") if @logger.is_a?(Logger)
        raise PacketException
      end
    end

    def register_topic_callback(topic, callback, &block)
      if topic.nil?
        @logger.error("The topics where the callback is trying to be registered have been found nil.") if @logger.is_a?(Logger)
        raise ArgumentError
      end
      remove_topic_callback(topic)
      if block_given?
        @registered_callback.push([topic, block])
      elsif !(callback.nil?) && callback.is_a?(Proc)
        @registered_callback.push([topic, callback])
      end
      MQTT_ERR_SUCCESS
    end

    def clear_topic_callback(topic)
      if topic.nil?
        @logger.error("The topics where the callback is trying to be unregistered have been found nil.") if @logger.is_a?(Logger)
        raise ArgumentError
      end
      @registered_callback.delete_if {|pair| pair.first == topic}
      MQTT_ERR_SUCCESS
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
      else
        handle_connack_error(packet.return_code)
      end
      config_all_message_queue
      flush_waiting_packet(true)     
      @on_connack.call(packet) unless @on_connack.nil?
      MQTT_CS_CONNECTED
    end

    def handle_pingresp
      @last_ping_resp = Time.now
    end

    def handle_suback(packet)
      max_qos = packet.return_codes
      id = packet.id
      if @subscriber.add_subscription(max_qos, id) == MQTT_ERR_SUCCESS
        @on_suback.call(adjust_qos) unless @on_suback.nil?
      end
    end

    def handle_unsuback(packet)
      id = packet.id
      if @subscriber.remove_subscription(id) == MQTT_ERR_SUCCESS
        @on_unsuback.call(to_unsub) unless @on_unsuback.nil?
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
        @logger.debug("Unable to connect to the server with the version #{@mqtt_version}, trying 3.1") if @logger.is_a?(Logger)
        if @mqtt_version != "3.1"
          @mqtt_version = "3.1"
          connect(@host, @port, @keep_alive)
        end
      when 0x02
        @logger.warn("Client Identifier is correct but not allowed by remote server.") if @logger.is_a?(Logger)
        MQTT_CS_DISCONNECTD
      when 0x03
        @logger.warn("Connection established but MQTT service unvailable on remote server.") if @logger.is_a?(Logger)
        MQTT_CS_DISCONNECTD
      when 0x04
        @logger.warn("User name or user password is malformed.") if @logger.is_a?(Logger)
        MQTT_CS_DISCONNECTD
      when 0x05
        @logger.warn("Client is not authorized to connect to the server.") if @logger.is_a?(Logger)
        MQTT_CS_DISCONNECTD
      end
    end
  end
end
