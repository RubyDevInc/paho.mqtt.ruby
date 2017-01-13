# encoding: BINARY

module PahoMqtt
  module Packet
    class Pingreq < PahoMqtt::Packet::Base
      # Create a new Ping Request packet
      def initialize(args={})
        super(args)
      end
    end
  end
end
