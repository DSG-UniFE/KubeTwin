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

        # assign a pod to a service
        # label is part of the pod's description
        def assignPod(pod)
            @pods[pod.label] ||= []
            raise 'Error! Pod is already present!' if @pods[label].include? pod

            # check
            if @selector == pod.label
                @pods[pod.label] << pod
            end
        end

        # who calls this method?
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