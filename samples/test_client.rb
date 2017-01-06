require "paho-mqtt"
require "logger"

file = File.open('paho.log', "a+")
log = Logger.new(file)
log.level = Logger::DEBUG

cli = PahoMqtt::Client.new({logger: log, persistent: true, keep_alive: 7})

cli.connect('localhost', 1883)

#########################################################
### Callback settings
waiting = true
cli.on_suback { waiting = false}

cli.on_message = lambda { |p|  puts ">>>>> This is a LAMBDA callback for message event <<<<<\nTopic: #{p.topic}\nPayload: #{p.payload}\nQoS: #{p.qos}" }

toto_toto = lambda { puts ">>>>> I am LAMBDA callback for the /toto/toto topic <<<<<" }
toto_tata = proc { puts ">>>>> I am PROC callback for the /toto/tata topic <<<<<" }


cli.add_topic_callback('/toto/tutu') do
  puts ">>>>> I am BLOCK callback for the /toto/tutu topic <<<<<" 
end
cli.add_topic_callback('/toto/tata', toto_tata)
cli.add_topic_callback('/toto/toto', toto_toto)

#########################################################

cli.subscribe(['/toto/toto', 0], ['/toto/tata', 1], ['/toto/tutu', 2], ["/toto", 0])

while waiting do
  sleep 0.0001
end

cli.publish("/toto/tutu", "It's me!", false, 2)
cli.publish("/toto/tutu", "It's you!", false, 1)
cli.publish("/toto/tutu", "It's them!", false, 0)

cli.publish("/toto/tata", "It's me!", false, 2)
cli.publish("/toto/tata", "It's you!", false, 1)
cli.publish("/toto/tata", "It's them!", false, 0)

cli.publish("/toto/toto", "It's me!", false, 2)
cli.publish("/toto/toto", "It's you!", false, 1)
cli.publish("/toto/toto", "It's them!", false, 0)

sleep cli.ack_timeout

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

sleep cli.ack_timeout

cli.unsubscribe('+/tutu', "+/+")

puts "Waiting 10 sec for keeping alive..."
sleep 10

cli.disconnect
