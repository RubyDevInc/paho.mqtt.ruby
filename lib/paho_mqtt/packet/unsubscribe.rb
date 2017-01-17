# encoding: BINARY

module PahoMqtt
  module Packet
    class Unsubscribe < PahoMqtt::Packet::Base
      # One or more topic paths to unsubscribe from
      attr_accessor :topics

      # Default attribute values
      ATTR_DEFAULTS = {
        :topics => [],
        :flags => [false, true, false, false],
      }

      # Create a new Unsubscribe packet
      def initialize(args={})
        super(ATTR_DEFAULTS.merge(args))
      end

      # Set one or more topic paths to unsubscribe from
      def topics=(value)
        if value.is_a?(Array)
          @topics = value
        else
          @topics = [value]
        end
      end

      # Get serialisation of packet's body
      def encode_body
        if @topics.empty?
          raise "no topics given when serialising packet"
        end
        body = encode_short(@id)
        topics.each { |topic| body += encode_string(topic) }
        return body
      end

      # Parse the body (variable header and payload) of a packet
      def parse_body(buffer)
        super(buffer)
        @id = shift_short(buffer)
        while(buffer.bytesize>0)
          @topics << shift_string(buffer)
        end
      end

      # Check that fixed header flags are valid for this packet type
      # @private
      def validate_flags
        if @flags != [false, true, false, false]
          raise "Invalid flags in UNSUBSCRIBE packet header"
        end
      end

      # Returns a human readable string, summarising the properties of the packet
      def inspect
        "\#<#{self.class}: 0x%2.2X, %s>" % [
          id,
          topics.map {|t| "'#{t}'"}.join(', ')
        ]
      end
    end
  end
end
