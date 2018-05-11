# Copyright (c) 2016-2017 Pierre Goudet <p-goudet@ruby-dev.jp>
#
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# and Eclipse Distribution License v1.0 which accompany this distribution.
#
# The Eclipse Public License is available at
#    https://eclipse.org/org/documents/epl-v10.php.
# and the Eclipse Distribution License is available at
#   https://eclipse.org/org/documents/edl-v10.php.
#
# Contributors:
#    Pierre Goudet - initial committer

module PahoMqtt
  class Publisher

    def initialize(sender)
      @waiting_puback  = []
      @waiting_pubrec  = []
      @waiting_pubrel  = []
      @waiting_pubcomp = []
      @puback_mutex    = Mutex.new
      @pubrec_mutex    = Mutex.new
      @pubrel_mutex    = Mutex.new
      @pubcomp_mutex   = Mutex.new
      @sender          = sender
    end

    def sender=(sender)
      @sender = sender
    end

    def send_publish(topic, payload, retain, qos, new_id)
      packet = PahoMqtt::Packet::Publish.new(
        :id      => new_id,
        :topic   => topic,
        :payload => payload,
        :retain  => retain,
        :qos     => qos
      )
      case qos
      when 1
        @puback_mutex.synchronize do
          if @waiting_puback.length >= MAX_PUBACK
            PahoMqtt.logger.error('PUBACK queue is full, could not send with qos=1') if PahoMqtt.logger?
            return MQTT_ERR_FAIL
          end
          @waiting_puback.push(:id => new_id, :packet => packet, :timestamp => Time.now)
        end
      when 2
        @pubrec_mutex.synchronize do
          if @waiting_pubrec.length >= MAX_PUBREC
            PahoMqtt.logger.error('PUBREC queue is full, could not send with qos=2') if PahoMqtt.logger?
            return MQTT_ERR_FAIL
          end
          @waiting_pubrec.push(:id => new_id, :packet => packet, :timestamp => Time.now)
        end
      end
      @sender.append_to_writing(packet)
      MQTT_ERR_SUCCESS
    end

    def do_publish(qos, packet_id)
      case qos
      when 0
      when 1
        send_puback(packet_id)
      when 2
        send_pubrec(packet_id)
      else
        PahoMqtt.logger.error("The packet QoS value is invalid in publish.") if PahoMqtt.logger?
        raise PacketException.new('Invalid publish QoS value')
      end
      MQTT_ERR_SUCCESS
    end

    def send_puback(packet_id)
      packet = PahoMqtt::Packet::Puback.new(
        :id => packet_id
      )
      @sender.append_to_writing(packet)
      MQTT_ERR_SUCCESS
    end

    def do_puback(packet_id)
      @puback_mutex.synchronize do
        @waiting_puback.delete_if { |pck| pck[:id] == packet_id }
      end
      MQTT_ERR_SUCCESS
    end

    def send_pubrec(packet_id)
      packet = PahoMqtt::Packet::Pubrec.new(
        :id => packet_id
      )
      @pubrel_mutex.synchronize do
        if @waiting_pubrel.length >= MAX_PUBREL
          PahoMqtt.logger.error('PUBREL queue is full, could not acknowledge qos=2') if PahoMqtt.logger?
          return MQTT_ERR_FAIL
        end
        @waiting_pubrel.push(:id => packet_id , :packet => packet, :timestamp => Time.now)
      end
      @sender.append_to_writing(packet)
      MQTT_ERR_SUCCESS
    end

    def do_pubrec(packet_id)
      @pubrec_mutex.synchronize do
        @waiting_pubrec.delete_if { |pck| pck[:id] == packet_id }
      end
      send_pubrel(packet_id)
      MQTT_ERR_SUCCESS
    end

    def send_pubrel(packet_id)
      packet = PahoMqtt::Packet::Pubrel.new(
        :id => packet_id
      )
      @pubcomp_mutex.synchronize do
        if @waiting_pubcomp.length >= MAX_PUBCOMP
          PahoMqtt.logger.error('PUBCOMP queue is full, could not acknowledge qos=2') if PahoMqtt.logger?
          return MQTT_ERR_FAIL
        end
        @waiting_pubcomp.push(:id => packet_id, :packet => packet, :timestamp => Time.now)
      end
      @sender.append_to_writing(packet)
      MQTT_ERR_SUCCESS
    end

    def do_pubrel(packet_id)
      @pubrel_mutex.synchronize do
        @waiting_pubrel.delete_if { |pck| pck[:id] == packet_id }
      end
      send_pubcomp(packet_id)
      MQTT_ERR_SUCCESS
    end

    def send_pubcomp(packet_id)
      packet = PahoMqtt::Packet::Pubcomp.new(
        :id => packet_id
      )
      @sender.append_to_writing(packet)
      MQTT_ERR_SUCCESS
    end

    def do_pubcomp(packet_id)
      @pubcomp_mutex.synchronize do
        @waiting_pubcomp.delete_if { |pck| pck[:id] == packet_id }
      end
      MQTT_ERR_SUCCESS
    end

    def config_all_message_queue
      config_message_queue(@waiting_puback, @puback_mutex)
      config_message_queue(@waiting_pubrec, @pubrec_mutex)
      config_message_queue(@waiting_pubrel, @pubrel_mutex)
      config_message_queue(@waiting_pubcomp, @pubcomp_mutex)
    end

    def config_message_queue(queue, mutex)
      mutex.synchronize do
        queue.each do |pck|
          pck[:timestamp] = Time.now
        end
      end
    end

    def check_waiting_publisher
      @sender.check_ack_alive(@waiting_puback, @puback_mutex)
      @sender.check_ack_alive(@waiting_pubrec, @pubrec_mutex)
      @sender.check_ack_alive(@waiting_pubrel, @pubrel_mutex)
      @sender.check_ack_alive(@waiting_pubcomp, @pubcomp_mutex)
    end

    def flush_publisher
      @puback_mutex.synchronize do
        @waiting_puback = []
      end
      @pubrec_mutex.synchronize do
        @waiting_pubrec = []
      end
      @pubrel_mutex.synchronize do
        @waiting_pubrel = []
      end
      @pubcomp_mutex.synchronize do
        @waiting_pubcomp = []
      end
    end
  end
end
