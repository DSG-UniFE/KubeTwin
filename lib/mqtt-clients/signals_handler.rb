require_relative './log_manager'  # Include the logging module


module SignalsHandler
# Setup the signal handler for Ctrl+C (SIGINT)
  # Maybe it's better to move this to a separate module (e.g., SignalManager). So to handle signals of every module.
  def self.setup_signal_handler(loggers)
    Signal.trap("INT") do
        puts "\nReceived SIGINT (Ctrl+C). Shutting down gracefully..."
        loggers[:info].info("Received SIGINT (Ctrl+C). Shutting down gracefully...")
        LogManager.stop_midnight_watcher # Stop the midnight watcher thread
      
      exit 0
    end
  end

end