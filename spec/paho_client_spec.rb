$:.unshift(File.dirname(__FILE__))

require 'spec_helper'

describe PahoMqtt::Client do
  context "From scrath" do
    it "Initialize the client with default parameter" do
      client = PahoMqtt::Client.new
      expect(client.host).to eq("")
      expect(client.port).to eq(1883)
      expect(client.mqtt_version).to eq('3.1.1')
      expect(client.clean_session).to be true
      expect(client.client_id).not_to be_nil
      expect(client.username).to be_nil
      expect(client.password).to be_nil
      expect(client.ssl).to be false
      expect(client.will_topic).to be_nil
      expect(client.will_payload).to be_nil    
      expect(client.will_qos).to eq(0)
      expect(client.will_retain).to be false
      expect(client.keep_alive).to eq(10)
      expect(client.ack_timeout).to eq(5)
      expect(client.on_connack).to be_nil
      expect(client.on_suback).to be_nil
      expect(client.on_unsuback).to be_nil
      expect(client.on_puback).to be_nil
      expect(client.on_pubrel).to be_nil
      expect(client.on_pubrel).to be_nil
      expect(client.on_pubcomp).to be_nil
      expect(client.on_message).to be_nil
    end

    it "Initialize the client paramter" do
      client = PahoMqtt::Client.new(
        :host => 'localhost',
        :port => 8883,
        :mqtt_version => '3.1.1',
        :clean_session => false,
        :client_id => "my_client1234",
        :username => 'Foo Bar',
        :password => 'barfoo',
        :ssl => true,
        :will_topic => "my_will_topic",
        :will_payload => "Bye Bye",
        :will_qos => 1,
        :will_retain => true,
        :keep_alive => 20,
        :ack_timeout => 3,
        :on_message => lambda { |packet| puts packet }
      )
      
      expect(client.host).to eq('localhost')
      expect(client.port).to eq(8883)
      expect(client.mqtt_version).to eq('3.1.1')
      expect(client.clean_session).to be false
      expect(client.client_id).to eq("my_client1234") 
      expect(client.username).to eq('Foo Bar')
      expect(client.password).to eq('barfoo')
      expect(client.ssl).to be true
      expect(client.will_topic).to eq("my_will_topic")
      expect(client.will_payload).to eq("Bye Bye")    
      expect(client.will_qos).to eq(1)
      expect(client.will_retain).to be true
      expect(client.keep_alive).to eq(20)
      expect(client.ack_timeout).to eq(3)
      expect(client.on_message.is_a?(Proc)).to be true
    end
    
    it "Initialize an empty client and set up the will" do
      client = PahoMqtt::Client.new
      client.config_will("Sample_topic", "Bye Bye", true, 1)
      expect(client.will_topic).to eq("Sample_topic")
      expect(client.will_payload).to eq("Bye Bye")
      expect(client.will_retain).to be true
      expect(client.will_qos).to eq(1)
    end
  end
  
  context "With a client carrying ssl" do
    let(:client) { PahoMqtt::Client.new(:ssl => true) }
    
    it "Set up a ssl context with key and certificate" do
      client.config_ssl_context(cert_path('client.crt'), cert_path('client.key'))
      expect(client.ssl_context.key).to be_a(OpenSSL::PKey::RSA)
      expect(client.ssl_context.cert).to be_a(OpenSSL::X509::Certificate)
    end

    it "Set up an ssl context with key, certificate and rootCA"do
      client.config_ssl_context(cert_path('client.crt'), cert_path('client.key'), cert_path('rootCA.pem.crt'))
      expect(client.ssl_context.ca_file).to eq(cert_path('rootCA.pem.crt'))
    end
  end

  context "With a defined host" do
    let(:client) { PahoMqtt::Client.new(:host => 'test.mosquitto.org') }
    before(:each) do
      expect(client.connection_state).to eq(PahoMqtt::Client::MQTT_CS_DISCONNECT)
    end
    
    it "Connect with unencrypted mode" do
      client.connect(client.host, client.port, 20)
      expect(client.keep_alive).to eq(20)
      expect(client.connection_state).to eq(PahoMqtt::Client::MQTT_CS_CONNECTED)
    end

    it "Connect with encrypted mode" do
      client.port = 8883
      client.config_ssl_context(cert_path('client.crt'), cert_path('client.key'))
      client.connect(client.host, client.port)
      expect(client.connection_state).to eq(PahoMqtt::Client::MQTT_CS_CONNECTED)
    end
   
    it "Connect and verify the on_connack callback" do
      connected = false
      client.on_connack do
        connected = true
      end
      client.connect
      expect(connected).to be true
    end
    
    it "Automaticaly try to reconnect after a unexpected disconnect on persistent mode" do
      client.ack_timeout = 2
      client.persistent = true
      client.connect(client.host, client.port, client.keep_alive, true)
      expect(client.connection_state).to eq(PahoMqtt::Client::MQTT_CS_CONNECTED)
      client.keep_alive = 0
      sleep 0.01
      expect(client.connection_state).to eq(PahoMqtt::Client::MQTT_CS_DISCONNECT)
      client.keep_alive = 15
      sleep client.ack_timeout
      expect(client.connection_state).to eq(PahoMqtt::Client::MQTT_CS_CONNECTED)      
    end

    it "Automaticaly disconnect after the keep alive on not persistent mode" do
      client.ack_timeout = 2
      client.connect(client.host, client.port)
      expect(client.connection_state).to eq(PahoMqtt::Client::MQTT_CS_CONNECTED)
      client.keep_alive = 0
      sleep 0.01
      expect(client.connection_state).to eq(PahoMqtt::Client::MQTT_CS_DISCONNECT)
      sleep client.ack_timeout
      expect(client.connection_state).to eq(PahoMqtt::Client::MQTT_CS_DISCONNECT)
    end
  end
  
  context "Already connected client" do
    let(:client) { PahoMqtt::Client.new(:host => 'test.mosquitto.org', :ack_timeout => 2) }
    let(:valid_topics) { Array({"/My_all_topic/#"=> 2, "My_private_topic" => 1}) }
    let(:invalid_topics) { Array({"" => 1, "topic_invalid_qos" => 42}) }
    let(:publish_content) { Hash(:topic => "My_private_topic", :payload => "Hello World!", :qos => 1, :retain => false) }
    
    before(:each) do
      client.connect(client.host, client.port)
      expect(client.connection_state).to eq(PahoMqtt::Client::MQTT_CS_CONNECTED)
    end

    it "Subscribe to valid topic and return success" do
      expect(client.subscribe(valid_topics)).to eq(PahoMqtt::Client::MQTT_ERR_SUCCESS)
    end
    
    it "Try to subscribe to nil topic and return success" do
      expect(client.subscribe(invalid_topics[1])).to eq(PahoMqtt::Client::MQTT_ERR_SUCCESS)
    end

    it "Subscribe to a topic and verifiy the on_suback callback"do
      subscribed = false
      client.on_suback = lambda { subscribed = true }
      client.subscribe(valid_topics)
      sleep client.ack_timeout
      expect(subscribed).to be true
    end
    
    # TODO: Add rescue in subscribe to catch the exception
    # it "Try to subscribe to valid topic with wrong qos" do
    #   
    #   expect(client.subscribe(invalid_topics[2])).to eq(SOME EXPECTION RETURN CODE)
    # end

    it "Unsubsribe to a valid topic" do
      expect(client.unsubscribe(valid_topics)).to eq(PahoMqtt::Client::MQTT_ERR_SUCCESS)
    end
    
    # TODO: Add rescue in unsubscribe to catch the exception
    # it "Try to unsubscribe from unvalid topic" do
    #   expect(client.unsubscribe([]).to eq(SOME EXPECTION RETURN CODE)
    # end
    
    it "Publish a packet to a valid topic"do
      expect(client.publish(publish_content[:topic], publish_content[:payload], publish_content[:retain], publish_content[:qos])).to eq(PahoMqtt::Client::MQTT_ERR_SUCCESS)
    end
    
    # TODO: Add rescue in publish to catch the exception
    # it "Pulish a packet to an invalid topic" do
    # end

    it "Publish to a topic and verify the on_message callback" do
      message = false
      client.on_message = proc { |packet| message = true }
      expect(message).to be false
      client.subscribe(valid_topics)
      client.publish(publish_content[:topic], publish_content[:payload], publish_content[:retain], publish_content[:qos])
      sleep client.ack_timeout
      expect(message).to be true
    end

    it "Publish to a topic and verify the callback registered for a specific topic" do
      message = false
      filter = false
      client.on_message = proc { message = true }
      client.add_topic_callback("/My_all_topic/topic1") do
        filter = true
      end
      expect(message).to be false
      expect(filter).to be false
      client.subscribe(valid_topics)
      client.publish(publish_content[:topic], publish_content[:payload], publish_content[:retain], publish_content[:qos])
      sleep client.ack_timeout
      expect(message).to be true
      expect(filter).to be false
      client.publish("/My_all_topic/topic1", "Hello World", false, 1)
      sleep client.ack_timeout
      expect(filter).to be true
    end

    it "Publish to a subscribed topic where callback is removed" do
      filter = false
      client.add_topic_callback("/My_all_topic/topic1") do
        filter = true
      end
      expect(filter).to be false
      client.subscribe(valid_topics)
      client.publish("/My_all_topic/topic1", "Hello World", false, 0)
      sleep client.ack_timeout
      expect(filter).to be true
      filter = false
      client.remove_topic_callback("/My_all_topic/topic1")
      client.publish("/My_all_topic/topic1", "Hello World", false, 0)      
      sleep client.ack_timeout
      expect(filter).to be false
    end

    it "Publish with qos 1 to subcribed topic and verfiy the on_puback callback" do
      puback = false
      client.on_puback do
        puback = true
      end
      expect(puback).to be false
      client.subscribe(valid_topics)
      client.publish(publish_content[:topic], publish_content[:payload], publish_content[:retain], 1)
      sleep client.ack_timeout
      expect(puback).to be true
    end
    
    it "Publish with qos 2 to subcribed topic and verfiy the on_puback callback" do
      pubrec = false
      pubrel = false
      pubcomp = false
      client.on_pubrec do
        pubrec = true
      end
      client.on_pubrel = proc { pubrel = true }
      client.on_pubcomp = lambda { pubcomp = true }
      expect(pubrec).to be false
      expect(pubrel).to be false
      expect(pubcomp).to be false
      client.subscribe(["My_test_qos_2_topic", 2])
      client.publish("My_test_qos_2_topic", "Foo Bar", false, 2)
      sleep client.ack_timeout
      expect(pubrec).to be true
      expect(pubrel).to be true
      expect(pubcomp).to be true
    end
  end
end
