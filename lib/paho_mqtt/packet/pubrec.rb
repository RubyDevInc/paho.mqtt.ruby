# encoding: BINARY

module PahoMqtt
  module Packet
    class Pubrec < PahoMqtt::Packet::Base
      # Get serialisation of packet's body
      def encode_body
        encode_short(@id)
      end

      # Parse the body (variable header and payload) of a packet
      def parse_body(buffer)
        super(buffer)
        @id = shift_short(buffer)
        unless buffer.empty?
          raise "Extra bytes at end of Publish Received packet"
        end
      end

      # Returns a human readable string, summarising the properties of the packet
      def inspect
        "\#<#{self.class}: 0x%2.2X>" % id
      end
    end
  end
end
