require "./paho_client"
require "./packet_manager"
require "pp"

cli = PahoRuby::Client.new
cli.ssl = true
cli.set_ssl_context("/Users/Pierre/certs/test/mykey.crt", "/Users/Pierre/certs/test/mykey.key")
cli.connect('test.mosquitto.org', 8883)

puts "ClientId : #{cli.client_id}"

#########################################################
### Callback settings

cli.on_message = lambda { |topic, payload, qos|  puts ">>>>> This is a LAMBDA callback for message event <<<<<\nTopic: #{topic}\nPayload: #{payload}\nQoS: #{qos}" }

toto_toto = lambda { puts ">>>>> I am LAMBDA callback for the /toto/toto topic <<<<<" }
toto_tata = proc { puts ">>>>> I am PROC callback for the /toto/tata topic <<<<<" }


cli.add_topic_callback('/toto/tutu') do
  puts ">>>>> I am BLOCK callback for the /toto/tutu topic <<<<<" 
end
cli.add_topic_callback('/toto/tata', toto_tata)
cli.add_topic_callback('/toto/toto', toto_toto)

#########################################################
sleep 1

cli.subscribe(['/toto/toto', 0], ['/toto/tata', 1], ['/toto/tutu', 2], ["/toto", 0])

sleep 2

cli.publish("/toto/tutu", "It's me!", false, 2)
cli.publish("/toto/tutu", "It's you!", false, 1)
cli.publish("/toto/tutu", "It's them!", false, 0)

cli.publish("/toto/tata", "It's me!", false, 2)
cli.publish("/toto/tata", "It's you!", false, 1)
cli.publish("/toto/tata", "It's them!", false, 0)

cli.publish("/toto/toto", "It's me!", false, 2)
cli.publish("/toto/toto", "It's you!", false, 1)
cli.publish("/toto/toto", "It's them!", false, 0)

sleep 3

cli.on_message = nil
toto_tutu = lambda { puts ">>>>> Changing callback type to LAMBDA for the /toto/tutu topic <<<<<" }
cli.add_topic_callback('/toto/tutu', toto_tutu)
cli.add_topic_callback('/toto/tata') do
  puts ">>>>> Changing callback type to BLOCK for the /toto/tata topic <<<<<"
end

cli.publish("/toto/tutu", "It's me!", false, 2)
cli.publish("/toto/tutu", "It's you!", false, 1)
cli.publish("/toto/tutu", "It's them!", false, 0)

cli.publish("/toto/tata", "It's me!", false, 2)
cli.publish("/toto/tata", "It's you!", false, 1)
cli.publish("/toto/tata", "It's them!", false, 0)

sleep 3
cli.unsubscribe('+/tutu', "+/+")
sleep 10

cli.disconnect
