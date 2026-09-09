require 'fileutils'
require 'logger'
require 'time'
require 'thread'

# Define a module for the log management system
module LogManager
  LOG_DIR = './logs'
  @current_log_folder = nil
  @current_date = nil
  @loggers = {}
  @midnight_thread = nil

  # Create log folder based on the current day
  def self.create_log_folder
    date_str = Time.now.strftime("%Y-%m-%d")
    daily_folder = File.join(LOG_DIR, date_str)
    FileUtils.mkdir_p(daily_folder) unless File.directory?(daily_folder)
    daily_folder
  end

  # Set up loggers for file logging and optional CLI logging
  def self.setup_loggers(enable_cli: false, enable_debug_log: true)
    setup_signal_handler ? setup_signal_handler : nil
    daily_folder = create_log_folder

    # Create log files for different severity levels
    file_loggers = {
      info: Logger.new(File.join(daily_folder, 'info.log')),
      error: Logger.new(File.join(daily_folder, 'error.log')),
      warn: Logger.new(File.join(daily_folder, 'warn.log')),
      fatal: Logger.new(File.join(daily_folder, 'fatal.log')),
      debug: enable_debug_log ? Logger.new(File.join(daily_folder, 'debug.log')) : nil
    }

    # Set up CLI logger if CLI logging is enabled
    cli_logger = enable_cli ? Logger.new(STDOUT) : nil

    # Set formatter for file loggers (and optional CLI logger)
    file_loggers.each_value do |logger|
      next unless logger # Skip nil loggers like the disabled debug logger
      logger.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} - #{severity}: #{msg}\n"
      end
    end

    if cli_logger
      cli_logger.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} - #{severity}: #{msg}\n"
      end
    end

    # Create combined loggers that log to file and optionally to CLI, and ensure all logs go to debug.log
    combined_loggers = {
      info: create_combined_logger(file_loggers[:info], file_loggers[:debug], cli_logger),
      error: create_combined_logger(file_loggers[:error], file_loggers[:debug], cli_logger),
      warn: create_combined_logger(file_loggers[:warn], file_loggers[:debug], cli_logger),
      fatal: create_combined_logger(file_loggers[:fatal], file_loggers[:debug], cli_logger),
      debug: file_loggers[:debug] # Directly use the debug logger
    }

    @loggers = combined_loggers  # Cache the loggers for future use
    start_midnight_watcher if @midnight_thread.nil?  # Start the midnight watcher if not already running
    combined_loggers  # Return the combined loggers
  end

  # Helper method to create a logger that logs to file, debug (if enabled), and CLI (if enabled)
  def self.create_combined_logger(file_logger, debug_logger = nil, cli_logger = nil)
    return file_logger unless file_logger # Ensure file_logger is valid

    multi_logger = Logger.new(file_logger.instance_variable_get(:@logdev).dev)

    # Define the method to log to file, debug (if enabled), and CLI (if enabled)
    multi_logger.formatter = proc do |severity, datetime, progname, msg|
      formatted_msg = "#{msg}"
      file_logger.add(Logger.const_get(severity), formatted_msg)
      debug_logger.add(Logger.const_get(severity), formatted_msg) if debug_logger # Log to debug if enabled
      cli_logger.add(Logger.const_get(severity), formatted_msg) if cli_logger # Log to CLI if enabled
      nil
    end

    multi_logger
  end

  # Start a background thread that checks for midnight and re-sets up loggers
  def self.start_midnight_watcher
    @midnight_thread ||= Thread.new do
      loop do
        now = Time.now
        next_midnight = Time.new(now.year, now.month, now.day) + 86400 # Midnight of the next day
        sleep_time = next_midnight - now
        sleep(sleep_time) # Sleep until midnight
        @loggers[:info].info("Midnight reached. Re-setting up loggers...")
        puts "Midnight reached. Re-setting up loggers..."
        setup_loggers # Re-setup loggers after midnight
      end
    end
  end

  # Stop the midnight watcher thread
  def self.stop_midnight_watcher
    @midnight_thread&.kill
    @midnight_thread = nil
  end


  # Setup the signal handler for Ctrl+C (SIGINT)
  # Maybe it's better to move this to a separate module (e.g., SignalManager). So to handle signals of every module.
  def self.setup_signal_handler
    Signal.trap("INT") do
      puts "\nReceived SIGINT (Ctrl+C). Shutting down gracefully..."
      stop_midnight_watcher # Stop the midnight watcher thread
      puts "Midnight watcher stopped."
      exit 0
    end
  end
end

# Example usage
if __FILE__ == $0
  enable_cli_logging = true # Set this to true to enable CLI logging
  enable_debug_logging = true # Set this to false to disable debug logging
  loggers = LogManager.setup_loggers(enable_cli: enable_cli_logging, enable_debug_log: enable_debug_logging)

  # Log messages (to log files, to debug.log, and optionally to CLI)
  if loggers
    loggers[:info].info("Connected to the broker...")
    loggers[:error].error("An error occurred...")
    loggers[:warn].warn("This is a warning message.")
    loggers[:fatal].fatal("A fatal error occurred.")
    loggers[:debug].debug("This is a debug message.") if enable_debug_logging
  else
    puts "Logger initialization failed."
  end

  # Simulate running for a while
  sleep(60 * 60) # Let the script run for 1 hour
end
