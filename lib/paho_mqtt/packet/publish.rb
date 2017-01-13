# encoding: BINARY

module PahoMqtt
  module Packet
    class Publish < PahoMqtt::Packet::Base
      # Duplicate delivery flag
      attr_accessor :duplicate

      # Retain flag
      attr_accessor :retain

      # Quality of Service level (0, 1, 2)
      attr_accessor :qos

      # The topic name to publish to
      attr_accessor :topic

      # The data to be published
      attr_accessor :payload

      # Default attribute values
      ATTR_DEFAULTS = {
        :topic => nil,
        :payload => ''
      }

      # Create a new Publish packet
      def initialize(args={})
        super(ATTR_DEFAULTS.merge(args))
      end

      def duplicate
        @flags[3]
      end

      # Set the DUP flag (true/false)
      def duplicate=(arg)
        if arg.kind_of?(Integer)
          @flags[3] = (arg == 0x1)
        else
          @flags[3] = arg
        end
      end

      def retain
        @flags[0]
      end

      # Set the retain flag (true/false)
      def retain=(arg)
        if arg.kind_of?(Integer)
          @flags[0] = (arg == 0x1)
        else
          @flags[0] = arg
        end
      end

      def qos
        (@flags[1] ? 0x01 : 0x00) | (@flags[2] ? 0x02 : 0x00)
      end

      # Set the Quality of Service level (0/1/2)
      def qos=(arg)
        @qos = arg.to_i
        if @qos < 0 or @qos > 2
          raise "Invalid QoS value: #{@qos}"
        else
          @flags[1] = (arg & 0x01 == 0x01)
          @flags[2] = (arg & 0x02 == 0x02)
        end
      end

      # Get serialisation of packet's body
      def encode_body
        body = ''
        if @topic.nil? or @topic.to_s.empty?
          raise "Invalid topic name when serialising packet"
        end
        body += encode_string(@topic)
        body += encode_short(@id) unless qos == 0
        body += payload.to_s.dup.force_encoding('ASCII-8BIT')
        return body
      end

      # Parse the body (variable header and payload) of a Publish packet
      def parse_body(buffer)
        super(buffer)
        @topic = shift_string(buffer)
        @id = shift_short(buffer) unless qos == 0
        @payload = buffer
      end

      # Check that fixed header flags are valid for this packet type
      # @private
      def validate_flags
        if qos == 3
          raise "Invalid packet: QoS value of 3 is not allowed"
        end
        if qos == 0 and duplicate
          raise "Invalid packet: DUP cannot be set for QoS 0"
        end
      end

      # Returns a human readable string, summarising the properties of the packet
      def inspect
        "\#<#{self.class}: " +
          "d#{duplicate ? '1' : '0'}, " +
          "q#{qos}, " +
          "r#{retain ? '1' : '0'}, " +
          "m#{id}, " +
          "'#{topic}', " +
          "#{inspect_payload}>"
      end

      protected

      def inspect_payload
        str = payload.to_s
        if str.bytesize < 16 and str =~ /^[ -~]*$/
          "'#{str}'"
        else
          "... (#{str.bytesize} bytes)"
        end
      end
    end
  end
end
