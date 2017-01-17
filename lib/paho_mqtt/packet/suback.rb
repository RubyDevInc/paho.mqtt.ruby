# encoding: BINARY

module PahoMqtt
  module Packet
    class Suback < PahoMqtt::Packet::Base
      # An array of return codes, ordered by the topics that were subscribed to
      attr_accessor :return_codes

      # Default attribute values
      ATTR_DEFAULTS = {
        :return_codes => [],
      }

      # Create a new Subscribe Acknowledgment packet
      def initialize(args={})
        super(ATTR_DEFAULTS.merge(args))
      end

      # Set the granted QoS value for each of the topics that were subscribed to
      # Can either be an integer or an array or integers.
      def return_codes=(value)
        if value.is_a?(Array)
          @return_codes = value
        elsif value.is_a?(Integer)
          @return_codes = [value]
        else
          raise "return_codes should be an integer or an array of return codes"
        end
      end

      # Get serialisation of packet's body
      def encode_body
        if @return_codes.empty?
          raise "no granted QoS given when serialising packet"
        end
        body = encode_short(@id)
        return_codes.each { |qos| body += encode_bytes(qos) }
        return body
      end

      # Parse the body (variable header and payload) of a packet
      def parse_body(buffer)
        super(buffer)
        @id = shift_short(buffer)
        while(buffer.bytesize>0)
          @return_codes << shift_byte(buffer)
        end
      end

      # Returns a human readable string, summarising the properties of the packet
      def inspect
        "\#<#{self.class}: 0x%2.2X, rc=%s>" % [id, return_codes.map{|rc| "0x%2.2X" % rc}.join(',')]
      end
    end
  end
end
