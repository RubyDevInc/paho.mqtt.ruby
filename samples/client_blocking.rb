require 'paho-mqtt'
require 'logger'

file = File.open('paho.log', "a+")
log = Logger.new(file)
log.level = Logger::DEBUG

client = PahoMqtt::Client.new({logger: log})

client.on_message do |pck|
  puts "New Message: #{pck.topic}\n>>> #{pck.payload}"
end

wait_suback = true
client.on_suback do |pck|
  wait_suback = false
end

client.connect('localhost', 1883, client.keep_alive, true, true)

Thread.new do
  while wait_suback do
    client.loop_read
    sleep 0.001
  end
end

client.subscribe(["topic_test", 2])
client.loop_write

loop do
  client.loop_read
  sleep 0.01
end
