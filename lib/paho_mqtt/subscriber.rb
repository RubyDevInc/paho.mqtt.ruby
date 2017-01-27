module PahoMqtt
  class Subscriber

    attr_reader :subscribed_topics

    def initialize(sender)
      @waiting_suback = []
      @waiting_unsuback = []
      @subscribed_mutex = Mutex.new
      @suback_mutex = Mutex.new
      @unsuback_mutex = Mutex.new
      @sender = sender
    end

    def config_subscription(new_id)
      unless @subscribed_topics == [] || @subscribed_topics.nil?
        packet = PahoMqtt::Packet::Subscribe.new(
          :id => new_id,
          :topics => subscribed_topics
        )
        @subscribed_mutex.synchronize {
          subscribed_topics = []
        }
        @suback_mutex.synchronize {
          @waiting_suback.push({ :id => new_id, :packet => packet, :timestamp => Time.now })
        }
        @sender.send_packet(packet)
      end
      MQTT_ERR_SUCCESS
    end

    def add_subscription(max_qos, packet_id, adjust_qos)
      @suback_mutex.synchronize {
        adjust_qos, @waiting_suback = @waiting_suback.partition { |pck| pck[:id] == packet_id }
      }
      if adjust_qos.length == 1
        adjust_qos = adjust_qos.first[:packet].topics
        adjust_qos.each do |t|
          if [0, 1, 2].include?(max_qos[0])
            t[1] = max_qos.shift
          elsif max_qos[0] == 128
            adjust_qos.delete(t)
          else
            @logger.error("The qos value is invalid in subscribe.") if logger?
            raise PacketException
          end
        end
      else
        @logger.error("The packet id is invalid, already used.") if logger?
        raise PacketException
      end
      @subscribed_mutex.synchronize {
        @subscribed_topics.concat(adjust_qos)
      }
      MQTT_ERR_SUCCESS
    end

    def remove_subscription(packet_id, to_unsub)
      @unsuback_mutex.synchronize {
        to_unsub, @waiting_unsuback = @waiting_unsuback.partition { |pck| pck[:id] == packet_id }
      }
      
      if to_unsub.length == 1
        to_unsub = to_unsub.first[:packet].topics
      else
        @logger.error("The packet id is invalid, already used.") if logger?
        raise PacketException
      end

      @subscribed_mutex.synchronize {
        to_unsub.each do |filter|
          @subscribed_topics.delete_if { |topic| match_filter(topic.first, filter.first) }
        end
      }
      MQTT_ERR_SUCCESS
    end
    
    def send_subscribe(topics, new_id)
      unless valid_topics?(topics) == MQTT_ERR_FAIL
        packet = PahoMqtt::Packet::Subscribe.new(
          :id => new_id,
          :topics => topics
        )        
        @sender.append_to_writing(packet)
        @suback_mutex.synchronize {
          @waiting_suback.push({ :id => new_id, :packet => packet, :timestamp => Time.now })
        }
        MQTT_ERR_SUCCESS
      else
        raise ProtocolViolation
      end
    end

    def send_unsubscribe(topics, new_id)
      unless valid_topics?(topics) == MQTT_ERR_FAIL
        packet = PahoMqtt::Packet::Unsubscribe.new(
          :id => new_id,
          :topics => topics
        )
        
        @sender.append_to_writing(packet)
        @unsuback_mutex.synchronize {
          @waiting_unsuback.push({:id => new_id, :packet => packet, :timestamp => Time.now})
        }
        MQTT_ERR_SUCCESS
      else
        raise ProtocolViolation
      end
    end

    def check_waiting_subscriber
      @sender.check_ack_alive(@waiting_suback, @suback_mutex, @waiting_suback.length)
      @sender.check_ack_alive(@waiting_unsuback, @unsuback_mutex, @waiting_unsuback.length)
    end

    def valid_topics?(topics)
      unless topics.length == 0
        topics.map do |topic|
          return MQTT_ERR_FAIL if topic.first == ""
        end
      else
        MQTT_ERR_FAIL
      end
      MQTT_ERR_SUCCESS
    end

    def match_filter(topics, filters)
      if topics.is_a?(String) && filters.is_a?(String)
        topic = topics.split('/')
        filter = filters.split('/')
      else
        @logger.error("Topics and filters are not found as String while matching topics to filter.") if logger?
        raise ParameterException
      end
      index = 0
      while index < [topic.length, filter.length].max do
        if topic[index].nil? || filter[index].nil?
          break
        elsif filter[index] == '#' && index == (filter.length - 1) 
          true
          break
        elsif filter[index] == topic[index] || filter[index] == '+'
          index = index + 1
        else
          break
        end
      end
      index == [topic.length, filter.length].max
    end
  end
end
