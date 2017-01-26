module PahoMqtt
  class Sender
    
    def initialize(socket)
      @socket = socket
      @writing_queue = []
      @writing_mutex = Mutex.new
      @last_ping_req = nil
    end

    def sending(packet)
      begin
        @socket.write(packet.to_s) unless @socket.nil? || @socket.closed?
        @last_ping_req = Time.now
        MQTT_ERR_SUCCESS
      rescue ::Exception
        raise WritingException
      end
    end

    def append_to_writing(packet)      
      @writing_mutex.synchronize {
        @writing_queue.push(packet)
      }
      MQTT_ERR_SUCCESS
    end

    def wrting_loop(max_packet)
      @writing_mutex.synchronize {
        cnt = 0
        while !@writing_queue.empty? && cnt < max_packet do
          send_packet(@writing_queue.shift)
          cnt += 1
        end
      }
      MQTT_ERR_SUCCESS
    end

    def flush_waiting_packet(sending=true)
      @writing_mutex.synchronize {
        @writing_queue.each do |m|
          send_packet(m)
        end
      }
    ensure
      @writing_queue = []
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
  end
end
