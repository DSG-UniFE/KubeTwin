# frozen_string_literal: true

require './services'

# this class is just a skeleton
# of kube-dns
# when a service is created is registred in the DNS
module SISFC
  class KubeDns
    # attr_reader :serviceName, :selector, :targetPort
    # keep it as simple as possible
    # this class keeps a list of services and provides lookup function
    def initialize
      # :service_label => reference_to_service
      @services = {}
    end

    # service is a reference to a Service object
    def registerService(service)
      # do we need null check here
      if @services.include? service.selector
        raise 'Error! Service is already present!'
        end

      @services[service.selector] = service
    end

    def deregisterService(service)
      raise 'Error! Service is not registred!' unless @services.include? service.selector

      @services.delete(service.selector)
    end

    # here name is the name of the Service
    # the name of the service corresponds to the label / selector
    def lookup(name)
      @services[name]
    end
  end
end
