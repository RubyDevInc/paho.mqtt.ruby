require 'openssl'
require 'socket'
require 'logger'

module PahoMqtt
  class Client
    # Connection related attributes:
    attr_accessor :host
    attr_accessor :port
    attr_accessor :mqtt_version
    attr_accessor :clean_session
    attr_accessor :persistent
    attr_accessor :blocking
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
    
    def initialize(*args)
      if args.last.is_a?(Hash)
        attr = args.pop
      else
        attr = {}
      end

      CLIENT_ATTR_DEFAULTS.merge(attr).each_pair do |k,v|
        self.send("#{k}=", v)
      end

      if @port.nil?
        @port
        if @ssl
          @port = DEFAULT_SSL_PORT
        else
          @port = DEFAULT_PORT
        end
      end

      if  @client_id.nil? || @client_id == ""
        @client_id = generate_client_id
      end

      @last_ping_resp = Time.now
      @last_packet_id = 0
      @ssl_context = nil
      @sender = nil
      @handler = nil
      @connection_helper = nil
      @connection_state = MQTT_CS_DISCONNECT
      @connection_state_mutex = Mutex.new
      @subscribed_topics = []
      @registered_callback = []
      @waiting_suback = []
      @waiting_unsuback = []
      @mqtt_thread = nil
      @reconnect_thread = nil
      @id_mutex = Mutex.new
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
    
    def connect(host=@host, port=@port, keep_alive=@keep_alive, persistent=@persistent, blocking=@blocking)
      @persistent = persistent
      @blocking = blocking
      @host = host
      @port = port.to_i
      @keep_alive = keep_alive
      @connection_state_mutex.synchronize {
        @connection_state = MQTT_CS_NEW
      }
      @mqtt_thread.kill unless @mqtt_thread.nil? 
      @connection_helper = PahoMqtt::ConnectionHelper.new
      @connection_helper.setup_connection(host, port, @ssl_context)
      @sender = @connection_helper.sender
      @connection_helper.send_connect(@mqtt_version, @clean_session, @keep_alive, @client_id, @username, @password, @will_topic,@will_payload, @will_qos, @will_retain)
      @sender.last_ping_req = Time.now
      @handler = @connection_helper.handler
      @connection_state = @connection_helper.do_connect(reconnect?)
      daemon_mode unless @blocking || !connected?
    end
    
    def daemon_mode
      @mqtt_thread = Thread.new do
        @reconnect_thread.kill unless @reconnect_thread.nil? || !@reconnect_thread.alive?
        while connected? do
          mqtt_loop
        end
      end
    end

    def connected?
      @connection_state == MQTT_CS_CONNECTED
    end

    def reconnect?
      Thread.current == @reconnect_thread
    end

    def loop_write(max_packet=MAX_WRITING)
      begin
        @sender.writing_loop(max_packet)
      rescue WritingException
        check_persistent
      end
    end

    def loop_read(max_packet=MAX_READ)
      max_packet.times do
        @handler.receive_packet(@socket)
      end
    end

    def mqtt_loop
      loop_read
      loop_write
      loop_misc
      sleep LOOP_TEMPO
    end

    def loop_misc
      if check_keep_alive(@persistent) == MQTT_CS_DISCONNECT
        disconnect(false)
        reconnect if persistent
      end
      @publisher.check_waiting_publisher
      @subscriber.check_waiting_subscriber
    end

    def reconnect(retry_time=RECONNECT_RETRY_TIME, retry_tempo=RECONNECT_RETRY_TEMPO)
      @reconnect_thread = Thread.new do
        retry_time.times do
          @logger.debug("New reconnect atempt...") if @logger.is_a?(Logger)
          connect
          if connected?
            break
          else
            sleep retry_tempo
          end
        end
        unless connected?
          @logger.error("Reconnection atempt counter is over.(#{RECONNECT_RETRY_TIME} times)") if @logger.is_a?(Logger)
          disconnect(false)
          exit
        end
      end
    end

    def disconnect(explicit=true)
      @last_packet_id = 0 if explicit
      @connection_helper.do_disconnect(@publisher, explicit, @mqtt_thread)
      @connection_state_mutex.synchronize {
        @connection_state = MQTT_CS_DISCONNECT
      }
      MQTT_ERR_SUCCESS
    end

    def publish(topic, payload="", retain=false, qos=0)
      if topic == "" || !topic.is_a?(String)
        @logger.error("Publish topics is invalid, not a string or empty.") if @logger.is_a?(Logger)
        raise ArgumentError
      end
      id = next_packet_id
      @publisher.send_publish(topic, payload, retain, qos, id)
    end

    def subscribe(*topics)
      begin
        unless @subscriber.send_subscribe(topics, id) == MQTT_ERR_SUCCESS
          check_persistent
        rescue ProtocolViolation
          @logger.error("Subscribe topics need one topic or a list of topics.") if @logger.is_a?(Logger)
          disconnect(false)
        end
      end
    end

    def unsubscribe(*topics)
      begin
        unless @subscriber.send_unsubscribe(topics, id) == MQTT_ERR_SUCCESS
          check_persistent
        rescue ProtocolViolation
          @logger.error("Unsubscribe need at least one topics.") if @logger.is_a?(Logger)
          disconnect(false)
        end
      end
    end

    def ping_host
      @sender.send_pingreq
    end

    def add_topic_callback(topic, callback=nil, &block)
      @handler.register_callback(topic, callback, &block)
    end

    def remove_topic_callback(topic)
      @handler.clear_topic_callback(topic)
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
      @id_mutex.synchronize {
        @last_packet_id = ( @last_packet_id || 0 ).next
      }
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

    def check_persistent
      disconnect(false)
      if @persistent
        reconnect
      else
        @logger.error("Trying to write a packet on a nil socket.") if @logger.is_a?(Logger)
        raise(::Exception)
      end
    end
  end
end
