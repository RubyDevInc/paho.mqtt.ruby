require "paho_mqtt/version"
require "paho_mqtt/client"
require "paho_mqtt/packet"
require 'logger'

module PahoMqtt
  extend self

  attr_accessor :logger

  # Default connection setup
  DEFAULT_SSL_PORT = 8883
  DEFAULT_PORT = 1883
  SELECT_TIMEOUT = 0
  LOOP_TEMPO = 0.005
  RECONNECT_RETRY_TIME = 3
  RECONNECT_RETRY_TEMPO = 5

  # MAX size of queue
  MAX_READ = 10
  MAX_PUBACK = 20
  MAX_PUBREC = 20
  MAX_PUBREL = 20
  MAX_PUBCOMP = 20
  MAX_WRITING = MAX_PUBACK + MAX_PUBREC + MAX_PUBREL  + MAX_PUBCOMP 

  # Connection states values
  MQTT_CS_NEW = 0
  MQTT_CS_CONNECTED = 1
  MQTT_CS_DISCONNECT = 2

  # Error values
  MQTT_ERR_SUCCESS = 0
  MQTT_ERR_FAIL = 1

  PACKET_TYPES = [
    nil,
    PahoMqtt::Packet::Connect,
    PahoMqtt::Packet::Connack,
    PahoMqtt::Packet::Publish,
    PahoMqtt::Packet::Puback,
    PahoMqtt::Packet::Pubrec,
    PahoMqtt::Packet::Pubrel,
    PahoMqtt::Packet::Pubcomp,
    PahoMqtt::Packet::Subscribe,
    PahoMqtt::Packet::Suback,
    PahoMqtt::Packet::Unsubscribe,
    PahoMqtt::Packet::Unsuback,
    PahoMqtt::Packet::Pingreq,
    PahoMqtt::Packet::Pingresp,
    PahoMqtt::Packet::Disconnect,
    nil
  ]

  CLIENT_ATTR_DEFAULTS = {
      :host => "",
      :port => nil,
      :mqtt_version => '3.1.1',
      :clean_session => true,
      :persistent => false,
      :blocking => false,
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
    
  Thread.abort_on_exception = true

  def logger=(logger_path)
    file = File.open(logger_path, "a+")
    log_file = Logger.new(file)
    log_file.level = Logger::DEBUG
    @action_manager.logger = log_file
  end

  def logger
    @logger
  end

  def logger?
    @logger.is_a?(Logger)
  end

  class Exception < ::Exception
  end

  class ProtocolViolation < PahoMqtt::Exception
  end

  class WritingException < PahoMqtt::Exception
  end

  class ReadingException < PahoMqtt::Exception
  end

  class PacketException < PahoMqtt::Exception
  end
end
