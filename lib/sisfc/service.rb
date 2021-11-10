require './pod'

module SISFC

    class Service

        attr_reader :serviceName, :selector, :targetPort

        def initialize(serviceName, selector, targetPort)
            @serviceName        = serviceName
            @selector           = selector
            @targetPort         = targetPort
            @pods               = {}
        end

        def assignPod(pod, label)
            @pods[label] ||= []
            raise 'Error! Pod is already present!' if @pods[label].include? pod
            
            if @selector == label
                @pods[label] << pod
            end
        end

        def get_random_pod(label, random: nil)
            if @pods.has_key? label
              if random
                @pods[label].sample(random: random)
              else
                @pods[label].sample
              end
            end
          end


    end

end