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
  sleep 0.01
end

### Waiting to assert that the message is displayed by on_message callback
sleep 1

### Calling an explicit disconnect
client.disconnect
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/PahoMqttRuby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

