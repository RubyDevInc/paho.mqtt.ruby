require 'benchmark'
require 'PahoMqttRuby'

client = PahoMqttRuby::Client.new(:host => 'localhost', :port => 1883)

client.connect
message = 0
client.on_message do
  message += 1
end

suback = true
client.on_suback { suback = false }
client.subscribe(["My_topic/levelx", 2])
while suback do
  sleep 0.001
end

payload = "a" * 128

Benchmark.bmbm do |x|
  x.report("Send 1 message with callback") do
    message = 0
    client.publish("My_topic/levelx", payload, false, 0)
    while message < 1 do
      sleep 0.001
    end
  end

  x.report("Send 10 messages with callback") do
    message = 0
    10.times do
      client.publish("My_topic/levelx", payload, false, 0)
    end
    while message < 10 do
      sleep 0.001
    end
  end

  x.report("Send #{PahoMqttRuby::Client::MAX_WRITING + 1} messages with callback (MAX_WRITING)") do
    message = 0
    (PahoMqttRuby::Client::MAX_WRITING + 1).times do
      client.publish("My_topic/levelx", payload, false, 0)
    end  
    while message < PahoMqttRuby::Client::MAX_WRITING do
      sleep 0.001
    end
  end

  x.report("Send 1000 messages with callback") do
    message = 0
    1000.times do
      client.publish("My_topic/levelx", payload, false, 0)
    end
    while message < 1000 do
      sleep 0.001
    end
  end
end

client.disconnect
  


