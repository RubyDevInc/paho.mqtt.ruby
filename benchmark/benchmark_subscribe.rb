require 'benchmark'
require 'PahoMqttRuby'



client = PahoMqttRuby::Client.new(:host => 'test.mosquitto.org', :port => 1883)

client.connect

Benchmark.bmbm do |x|
  suback = false
  client.on_suback { suback = true}
  x.report("Subscribe to topic") do
    client.subscribe(["My_topic/levelx", 2])
    while !suback do
      sleep 0.0001
    end
  end  
end
client.disconnect
  


