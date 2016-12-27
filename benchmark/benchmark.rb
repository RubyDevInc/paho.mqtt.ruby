require 'benchmark'
require 'PahoMqttRuby'



client = PahoMqttRuby::Client.new(:host => 'localhost', :port => 1883)

client.connect
message = 0

Benchmark.bmbm do |x|
  # x.report("initialize simple:") { PahoMqttRuby::Client.new }
  # x.report("initialize half: ") do
  #   PahoMqttRuby::Client.new(
  #     :host => 'localhost',
  #     :port => 1883,
  #     :mqtt_version => '3.1.1',
  #     :clean_session => false,
  #     :client_id => "my_client1234",
  #     :username => 'Foo Bar',
  #     :password => 'barfoo',
  #     :ssl => true,
  #     :will_topic => "my_will_topic",
  #     :will_payload => "Bye Bye",
  #     :will_qos => 1,
  #     :will_retain => true,
  #     :keep_alive => 20,
  #     :ack_timeout => 3,
  #     :on_message => lambda { |packet| puts packet }
  #   )
  # end
  
  # x.report("Connect unencrypted mode:") { client.connect }

  # suback = false
  # client.on_suback { suback = true}
  # x.report("Subscribe to topic") do
  #   client.subscribe(["My_topic/levelx", 0])
  #   while !suback do
  #     sleep 0.0001
  #   end
  # end
  # suback = false
  # client.on_suback { suback = true}
  # client.subscribe(["My_topic/levelx", 1])
  # while !suback do
  #   sleep 0.001
  # end

  client.on_message do
    message += 1
  end

  x.report("Send 1 message with callback") do
    message = 0
    client.publish("My_topic/levelx", "Foo", false, 0)
    while message < 1 do
      sleep 0.001
    end
  end

  x.report("Send 10 messages with callback") do
    message = 0
    10.times do
      client.publish("My_topic/levelx", "Foo", false, 0)
    end
    while message < 10 do
      sleep 0.001
    end
  end

  x.report("Send #{PahoMqttRuby::Client::MAX_WRITING + 1} messages with callback (MAX_WRITING)") do
    message = 0
    (PahoMqttRuby::Client::MAX_WRITING + 1).times do
      client.publish("My_topic/levelx", "Foo", false, 0)
    end  
    while message < PahoMqttRuby::Client::MAX_WRITING do
      sleep 0.001
    end
  end

  x.report("Send 1000 messages with callback") do
    message = 0
    1000.times do
      client.publish("My_topic/levelx", "Foo", false, 0)
    end
    while message < 1000 do
      sleep 0.001
    end
  end
end
client.disconnect
  


