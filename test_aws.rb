require "./paho_client"
require "./packet_manager"
require "json"

cli = PahoRuby::Client.new
cli.ssl = true
cli.set_ssl_context("/Users/Pierre/certs/certificate.pem.crt", "/Users/Pierre/certs/private.pem.key", "/Users/Pierre/certs/root-CA.crt")

cli.connect('a15ipmbgzhr3uc.iot.ap-northeast-1.amazonaws.com', 8883)
sleep 2

cli.subscribe(["topic1", 1])
sleep 2

cli.publish("topic1", "Hi there! My name is PahoRuby.", false, 1)
payload = JSON.generate({ :state => { :desired => { :aisatsu => "Hello" }}})

cli.publish("$aws/things/MyRasPi/shadow/update", payload, false, 1)
sleep 2

cli.disconnect
