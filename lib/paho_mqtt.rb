require "paho.mqtt/version"
require "paho.mqtt/client"
require "paho.mqtt/packet"

module PahoMqtt

  # Default connection setup
  DEFAULT_SSL_PORT = 8883
  DEFAULT_PORT = 1883
  SELECT_TIMEOUT = 0
  LOOP_TEMPO = 0.005
  RECONNECT_RETRY_TIME = 3
  RECONNECT_RETRY_TEMPO = 5

  # MAX size of queue
  MAX_PUBACK = 20
  MAX_PUBREC = 20
  MAX_PUBREL = 20
  MAX_PUBCOMP = 20
  MAX_WRITING = MAX_PUBACK + MAX_PUBREC + MAX_PUBREL  + MAX_PUBCOMP 
    
  # Connection states values
  MQTT_CS_NEW = 0
  MQTT_CS_CONNECTED = 1
  MQTT_CS_DISCONNECT = 2
  MQTT_CS_CONNECT_ASYNC = 3
  
  # Error values
  MQTT_ERR_SUCCESS = 0
  MQTT_ERR_FAIL = 1

  Thread.abort_on_exception = true
  
  class Exception < ::Exception
  end

  class ProtocolViolation < PahoMqtt::Exception
  end

  class ParameterException < PahoMqtt::Exception
  end

  class PacketException < PahoMqtt::Exception
  end
end
