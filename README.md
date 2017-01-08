# PahoMqtt

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/PahoMqttRuby`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'paho-mqtt'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install paho-mqtt

## Usage

### Getting started
The following samples files cover the main features of the client:
```ruby
require 'paho-mqtt'

### Create a simple client with default attributes
client = PahoMqtt::Client.new

### Register a callback on message event to display messages
message_counter = 0
client.on_message do |message|
  puts "Message recieved on topic: #{message.topic}\n>>> #{message.payload}"
  message_counter += 1
end

### Register a callback on suback to assert the subcription
waiting_suback = true
client.on_suback do
  waiting_suback = false
  puts "Subscribed"
end

### Register a callback for puback event when receiving a puback
waiting_puback = true
client.on_puback do
  waiting_puback = false
  puts "Message Acknowledged"
end

### Connect to the eclipse test server on port 1883 (Unencrypted mode)
client.connect('iot.eclipse.org', 1883)

### Subscribe to a topic
client.subscribe(['/paho/ruby/test', 2])

### Waiting for the suback answer and excute the previously set on_suback callback
while waiting_suback do
  sleep 0.001
end

### Publlish a message on the topic "/paho/ruby/test" with "retain == false" and "qos == 1"
client.publish("/paho/ruby/test", "Hello there!", false, 1)

while waiting_puback do
  sleep 0.001
end

### Waiting to assert that the message is displayed by on_message callback
sleep 1

### Calling an explicit disconnect
client.disconnect
```

### Client
#### Initialization
The client may be initialized without paramaters or with a hash of parameters. The list of client's accessor is details in the next parts. A client id would be generated if not provided, a default port would be also set (8883 if ssl set, else 1883).
```ruby
client = PahoMqtt::Client.new
#Or
client = PahoMqtt::Client.new({host: ..., port: ..., ssl: false})
```
### Accessor
The client have many accessor that configure the client depending on yours need. The accessor could be splited in three differents roles, connection setup, last will setup, time-out setup and callback setup.
Connection setup:
```
* host          : The endpoint where the client would try to connect (defaut "")
* port          : The port on the remote host where the socket would try to connect (default nil)
* mqtt_version  : The version of MQTT protocol used to communication (default 3.1.1)
* clean_session : If set to false, ask the message broker to try to restore the previous session (default true)
* persistent    : Keep the client connected even after keep alive, automaticaly try to reconnect on failure (default false)
* client_id     : The identifier of the client (default nil)
* username      : The username if the server require authentication (default nil)
* password      : The password of the user if authentication required (default nil)
* ssl           : Requiring the encryption for the communication (default false)
```

Last Will:
```
* will_topic   : The topic where to publish the last will (default nil)
* will_payload : The message of the last will (default "")
* will_qos     : The qos of the last will (default 0)
* will_retain  : The retain status of the last will
```

Time-out:
```
* keep_alive  : The reference timer after which the client should decide to keep the connection alive or not
* ack_timeout : The timer after which a non-acknowledged packet is considered as a failure
```

The description of the callback accessor is detailed in the section dedicated to the callbacks. The client also have three read only attributes which provided information on the client state.
```
* registered_callback : The list of topics where callback have been registred which the associated callback
* subscribed_topics   : The list of the topics where the client is currentely receiving publish.
* connection_state    : The state of the connection between the message broker and the client
```


## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/PahoMqttRuby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

