require 'paho-mqtt'

client = PahoMqtt::Client.new

client.on_connack = proc { puts "Successfully Connected" }

client.on_message do |packet|
  puts "New message received on topic: #{packet.topic}\n>>>#{packet.payload}"
end

specific_callback = lambda { |packet| puts "Specific callback for #{packet.topic}" }
client.add_topic_callback("/foo/bar", specific_callback)
# Or
client.add_topic_callback("/foo/bar") do |packet|
  puts "Specific callback for #{packet.topic}"
end

### This will connect to the message broker excute the mqtt_loop (socket reading/writing) in the background
client.connect('iot.eclipse.org', 1883, client.persistence, true)


### Subscribe to two topics with maximum qos associated
client.subscribe(["/foo/bar", 1], ["/foo/foo/", 2])

### Publish to the topics "/foo/bar", with qos = 1 and no retain
client.publish("/foo/bar", "Hello Wourld!", false, 1)

### This only connect to the message broker, nothing more
client.connect('iot.eclipse.org', 1883, client.persistence, false)

client.remove_topic_callback("/foo/bar")

client.disconnect
