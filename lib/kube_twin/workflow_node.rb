module KUBETWIN
    class WorkflowNode
        attr_accessor :name, :children
      
        def initialize(name)
          @name = name
          @children = []
        end
      
        def add_child(node)
          @children << node
        end

        # Get the child node of a given name
        # This method should also explore the children of the children
        def get_child_of(name)
            children.each do |child|
                return child if child.name == name
                return child.get_child_of(name) if child.children.any?
            end
            nil
        end

        # Recursive search to count the size of the tree
        # count all valid names in the tree, explore all children
        # and their children
        def count_children
            count = 1
            children.each do |child|
                count += child.count_children
            end
            count
        end

        def size
            count_children - 1
        end
      
        def to_s(indent = 0)
            "#{'  ' * indent}#{name}\n" + children.map { |child| child.to_s(indent + 1) }.join
        end
      
        def self.build_workflow(name, config)
            node = WorkflowNode.new(name)
            config.each do |child_name, child_config|
                if child_config.is_a?(Hash)
                    child_node = build_workflow(child_name, child_config)
                elsif child_config.is_a?(Array)
                    child_node = WorkflowNode.new(child_name)
                    child_config.each do |grandchild_name|
                    grandchild_node = WorkflowNode.new(grandchild_name)
                    child_node.add_child(grandchild_node)
                    end
                else
                    child_node = WorkflowNode.new(child_name)
                end
                node.add_child(child_node)
            end
            node
        end 
    end
end