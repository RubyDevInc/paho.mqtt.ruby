require 'openssl'

module PahoMqtt
  module SSLHelper
    extend self

    def config_ssl_context(cert_path, key_path, ca_path=nil)
      ssl_context = OpenSSL::SSL::SSLContext.new
      set_cert(cert_path, ssl_context)
      set_key(key_path, ssl_context)
      set_root_ca(ca_path, ssl_context)
      ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER unless ca_path.nil?
      ssl_context
    end

    def set_cert(cert_path, ssl_context)
      ssl_context.cert = OpenSSL::X509::Certificate.new(File.read(cert_path))
    end

    def set_key(key_path, ssl_context)
      ssl_context.key = OpenSSL::PKey::RSA.new(File.read(key_path))
    end

    def set_root_ca(ca_path, ssl_context)
      ssl_context.ca_file = ca_path
    end
  end
end
