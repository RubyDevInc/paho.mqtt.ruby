require "./paho_client"
require "./packet_manager"
require "json"

cli = PahoRuby::Client.new
cli.ssl = true
cli.set_ssl_context("/Users/Pierre/certs/certificate.pem.crt", "/Users/Pierre/certs/private.pem.key", "/Users/Pierre/certs/root-CA.crt")

cli.connect('a15ipmbgzhr3uc.iot.ap-northeast-1.amazonaws.com', 8883)

cli.subscribe(["topic1", 1], ["topic2", 1])
sleep 2

#cli.on_message = lambda { |topic, payload, qos|  puts ">>>>> This is a LAMBDA callback for message event <<<<<\nTopic: #{topic}\nPayload: #{payload}\nQoS: #{qos}" }

cli.add_topic_callback('topic1') do
  puts "I am callback for topic 1"
end

cli.add_topic_callback('topic2') do
  puts "I am callback for topic 2"
end

cli.publish("topic1", "Hi there! My name is PahoRuby.", false, 1)
cli.publish("topic2", "Hi there! My name is PahoRuby2.", false, 1)

#payload = JSON.generate({ :state => { :desired => { :aisatsu => "こんばは" }}})
#cli.publish("$aws/things/MyRasPi/shadow/update", payload, false, 1)
sleep 2

cli.disconnect
