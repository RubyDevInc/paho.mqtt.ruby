$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'PahoMqttRuby'

def cert_path(file)
  File.join(File.dirname(__FILE__), 'certs_spec', file.to_s)
end
