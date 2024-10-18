require 'open3'


def exec_KT(conf_filename)
    command = 'bundle exec ../../bin/kube_twin ' + conf_filename
    stdout, stderr, status = Open3.capture3(command)  # Replace 'ls' with your command
    if status.success?
        puts "Command executed successfully: #{stdout}"
        stdout
      else
        puts "Command failed: #{stderr}"
        nil
      end
    return stdout
end

if __FILE__ == $0
  conf_filename = 'tosca_my_solver_3.conf'
  result = exec_KT(conf_filename)

  if result.nil?
    puts "Execution of #{conf_filename} failed."
  else
    puts "Execution result:\n#{result}"
  end
end
