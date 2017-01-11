# PahoMqtt

The followings files describes the Paho Mqtt client API for the ruby programming language. It enable applications to connect to an MQTT message broker threw the MQTT protocol (versions 3.1.1). MQTT is a lightweight protocol designed for IoT/M2M.


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
client = PahoMqtt::Client.new({host: "iot.eclispe.org", port: 1883, ssl: false})
```
#### Client's parameters
The client have many accessors which help to configure the client depending on yours need. The different accessors could be splited in three roles, connection setup, last will setup, time-out setup and callback setup.
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
* will_retain  : The retain status of the last will (default false)
```

Timers:
```
* keep_alive  : The reference timer after which the client should decide to keep the connection alive or not
* ack_timeout : The timer after which a non-acknowledged packet is considered as a failure
```

The description of the callback accessor is detailed in the section dedicated to the callbacks. The client also have three read only attributes which provided information on the client state.
```
* registered_callback : The list of topics where callback have been registred which the associated callback
* subscribed_topics   : The list of the topics where the client is currentely receiving publish.
* connection_state    : The current state of the connection between the message broker and the client
```

### Connection configuration
#### Unencrypted mode
The most simple connection way is the unencrypted mode. All data would be send clearly to the message broker, also it might not be safe for sensitive data. The connection may set or override some parameters of the client, the host, the port, the keep_alive timer and the persistence mode.
```ruby
client.connect
# Or
client.connect("iot.eclipse.org", 1883, client.keep_alive, client.persistent)
```

#### Encrypted mode
The client support the encrypt connection threw tls-ssl socket. For using this mode, the ssl flag of the client shoudl be set to 'true'.   
``` ruby
client.ssl
client.config_ssl_context(certificate_path, key_path)
client.connect("test.mosquitto.org", 8883)
# Or if rootCA is needed
client.config_ssl_context(certificate_path, key_path, rootCA_path)
client.connect("test.mosquitto.org", 8884)
```

#### Persistence
The client hold a keep_alive timer which the reference time that the connection should be hold without any activity form the message broker. The persistence flag, when set to True, enable the client to be more independent from the keep_alive timer. Just before the keep_alive run out, the client sent a ping request to tell to the message broker that the connection should be kept. The persistent mode also enable the client to automatically reconnect to the message broker after the keep_alive timer run out.
When the client's persistence flag is set to False, it just simply disconnect when the keep_alive timer runs out.  

#### Foreground and Deamon
The client client could be connect to the message broker using the main thread in forground or as a daemon in a seperate thread. The default mode is daemon mode, the deamon would excute in the background the read/write operation as weell as the control of the timers. If the client is connected using the main thread, all operation should be performed by the user, using the different control loops. There is four different loops which roles is details in the next par
t.
```ruby
### This will connect to the message broker excute the mqtt_loop (socket reading/writing) in the background
client.connect('iot.eclipse.org', 1883, client.persistence, true)


### This only connect to the message broker, nothing more
client.connect('iot.eclipse.org', 1883, client.persistence, false)
```

### Control loops
#### Reading loops
The reading loop provide access to the socket in a reading mode. Periodically, the sockets would be inspect to try to find a mqtt packet. The read loop accept a parameter which is number of loop's turn. The default value is five turn.  
The default value is define in the PahoMqtt module as the constant PahoMqtt::MAX_READ, another that could be modify is the socket inspection period. The referring constant is SELECT_TIMEOUT (PahoMqtt::SELECT_TIMEOUT) and its default value is 0.  

#### Writing loop
The writing loop would send the packets which have been previously stack by MQTT operations. This loop also accept a parameter whih is the maximum packet to write as MAX_WRITING (PahoMqtt::MAX_WRITING). The writing loop exit if the maximum number of packet have been sent or if the waiting packet queue is empty.

#### Miscellaneous loop
The misc loop perform different control operations on the packets state and the connection state. The loop parse the different queue of packet that are waiting for an acknolegement. If the ack_timeout of a packet had run out, the packet is resent. The size of the different waiting queue is defined as module constants. This loop also assert that the connection is still available by checking the keep_alive timers.

### Subscription
In order to read the message sent on a topic by a the message broker, the client should subscribe to this topic. The client enable to subscribe to several topics in the same request. The subscription could also be done by using wildcard details in the MQTT specifications. Each topic is subscribe with a maximum qos level, only message with a qos level lower or equal to this value would be published to the client. The subscribe command accept one or several pair composed by the topic (or wildcard) and the maximum qos level.  
```ruby
### Subscribe to two topics with maximum qos associated
client.subscribe(["/foo/bar", 1], ["/foo/foo/", 2])
```
  
The subscription is persistent, in case of a unexpected disconnect, the current subscription state is saved and new subscribed request is sent to message broker.

### Publishing
User data could be sent to the message broker with the publish operation. A publish operation require a topic, and payload (user data), two other parameter may be configured, retain and qos. The retain flag tell to the message broker to keep the current publish packet, see the MQTT protocol specifications for more details. The qos enable different level of control on the publish package. The client support the three level of qos (0, 1 and 2), see the MQTT protocol specifications for qos level details. The default retain value is False and the qos level is 0.  
```ruby
### Publish to the topics "/foo/bar", with qos = 1 and no retain
client.publish("/foo/bar", "Hello Wourld!", false, 1)
```

### Handlers and Callbacks
#### Handlers
When a packet is recieved and inspected, a appropriate handler is called. The handlers perform different control operation such as update the connection state, update the subscribed topics, and send publish control packets. Each packet has a specific handler. Before returning the handler execute a callback if the user configured one for this type of packet. The handler of pingreq and pingresp packets does not perform callbacks, and the publish handler may execute sequencially two callbacks. One for the reception of the generic publish packet and another if the user has configured a callback for the topic where the publish have been received.  

#### Callbacks
The callbacks could be defined in a three different ways, as block, as Proc or as Lambda. The callback have access to the packet that had trigger it.  
```ruby
### Register a callback trigger on the reception of a CONNACK packet
client.on_connack = proc { puts "Successfully Connected" }

### Register a callback trigger on the reception of PUBLISH packet
client.on_message do |packet|
  puts "New message received on topic: #{packet.topic}\n>>>#{packet.payload}"
end
```

A callback could be configured for every specific topics. The list of topics where a callbacks have been registered could be read at any time, threw the registered_callback variable. The following example details how to manage callbacks for specific topics.  
```ruby
### Add a callback for every message received on /foo/bar
specific_callback = lambda { |packet| puts "Specific callback for #{packet.topic}" }
client.add_topic_callback("/foo/bar", specific_callback)
# Or
client.add_topic_callback("/foo/bar") do |packet|
  puts "Specific callback for #{packet.topic}"
end

### To remove a callback form a topic
client.remove_topic_callback("/foo/bar")
```

### Message Broker, Mosquitto
Mosquitto is a message broker support by Eclipse which is quite easy-going. In order to run spec or samples files, a message broker is needed. Mosquitto enable to run locally a message broker, it could be configured with the mosquitto.conf files. See Mosquitto message broker page for more details.

