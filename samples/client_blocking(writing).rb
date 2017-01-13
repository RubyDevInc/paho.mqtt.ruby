require 'paho-mqtt'
require 'logger'

file = File.open('paho_writting.log', "a+")
log = Logger.new(file)
log.level = Logger::DEBUG

client = PahoMqtt::Client.new({logger: log})

client.connect('localhost', 1883, client.keep_alive, true, true)

loop do
  client.publish("topic_test", "Hello, Are you there?", false, 1)
  client.loop_write
  sleep 1
end
