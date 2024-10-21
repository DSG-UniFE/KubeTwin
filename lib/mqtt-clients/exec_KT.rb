require 'open3'
require 'logger'

module ExecKubeTwin
  # Function to execute the KubeTwin command

  def self.exec_KT(conf_filename, loggers)
    command = "bundle exec ../../bin/kube_twin #{conf_filename}"
    
    # Log the start of command execution
    loggers[:info].info("Executing command: #{command}")
    
    # Run the command
    stdout, stderr, status = Open3.capture3(command)
    
    if status.success?
      # Log successful execution and output
      loggers[:info].info("Command executed successfully: #{status}")
      stdout
    else
      # Log the error message
      loggers[:error].error("Command failed: #{stderr}")
      nil
    end
  end
end

if __FILE__ == $0

    # Usage of the module in the same file
    # Setup logging
    loggers = {
        info: Logger.new(STDOUT),
        error: Logger.new(STDOUT)
}
    
  conf_filename = 'tosca_my_solver_3.conf'
  
  # Log the beginning of execution
  loggers[:info].info("Starting execution of #{conf_filename}")
  
  result = ExecKubeTwin.exec_KT(conf_filename, loggers)

  if result.nil?
    # Log the failure message
    loggers[:error].error("Execution of #{conf_filename} failed.")
  else
    # Log the successful result
    loggers[:info].info("Execution result:\n#{result}")
  end
end
