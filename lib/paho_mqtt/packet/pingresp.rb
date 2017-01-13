# encoding: BINARY

module PahoMqtt
  module Packet
    class Pingresp < PahoMqtt::Packet::Base
      # Create a new Ping Response packet
      def initialize(args={})
        super(args)
      end

      # Check the body
      def parse_body(buffer)
        super(buffer)
        unless buffer.empty?
          raise "Extra bytes at end of Ping Response packet"
        end
      end
    end
  end
end
