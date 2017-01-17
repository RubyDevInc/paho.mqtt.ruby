# encoding: BINARY

module PahoMqtt
  module Packet
    class Disconnect < PahoMqtt::Packet::Base
      # Create a new Client Disconnect packet
      def initialize(args={})
        super(args)
      end
      
      # Check the body
      def parse_body(buffer)
        super(buffer)
        unless buffer.empty?
          raise "Extra bytes at end of Disconnect packet"
        end
      end
    end
  end
end
