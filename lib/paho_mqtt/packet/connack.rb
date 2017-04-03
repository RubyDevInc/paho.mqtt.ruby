# encoding: BINARY
### original file from the ruby-mqtt gem
### located at https://github.com/njh/ruby-mqtt/blob/master/lib/mqtt/packet.rb
###
### The MIT License (MIT)

### Copyright (c) 2009-2013 Nicholas J Humfrey

### Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without

### restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the

### Software is furnished to do so, subject to the following conditions:

### The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software
###
### THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
### WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NON INFRINGEMENT. IN NO EVENT SHALL THE AUTHORS
### OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
### OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
module PahoMqtt
  module Packet
    class Connack < PahoMqtt::Packet::Base
      # Session Present flag
      attr_accessor :session_present

      # The return code (defaults to 0 for connection accepted)
      attr_accessor :return_code

      # Default attribute values
      ATTR_DEFAULTS = {:return_code => 0x00}

      # Create a new Client Connect packet
      def initialize(args={})
        # We must set flags before other attributes
        @connack_flags = [false, false, false, false, false, false, false, false]
        super(ATTR_DEFAULTS.merge(args))
      end

      # Get the Session Present flag
      def session_present
        @connack_flags[0]
      end

      # Set the Session Present flag
      def session_present=(arg)
        if arg.kind_of?(Integer)
          @connack_flags[0] = (arg == 0x1)
        else
          @connack_flags[0] = arg
        end
      end

      # Get a string message corresponding to a return code
      def return_msg
        case return_code
        when 0x00
          "Connection Accepted"
        when 0x01
          "Connection refused: unacceptable protocol version"
        when 0x02
          "Connection refused: client identifier rejected"
        when 0x03
          "Connection refused: server unavailable"
        when 0x04
          "Connection refused: bad user name or password"
        when 0x05
          "Connection refused: not authorised"
        else
          "Connection refused: error code #{return_code}"
        end
      end

      # Get serialisation of packet's body
      def encode_body
        body = ''
        body += encode_bits(@connack_flags)
        body += encode_bytes(@return_code.to_i)
        return body
      end

      # Parse the body (variable header and payload) of a Connect Acknowledgment packet
      def parse_body(buffer)
        super(buffer)
        @connack_flags = shift_bits(buffer)
        unless @connack_flags[1,7] == [false, false, false, false, false, false, false]
          raise "Invalid flags in Connack variable header"
        end
        @return_code = shift_byte(buffer)
        unless buffer.empty?
          raise "Extra bytes at end of Connect Acknowledgment packet"
        end
      end

      # Returns a human readable string, summarising the properties of the packet
      def inspect
        "\#<#{self.class}: 0x%2.2X>" % return_code
      end
    end
  end
end
