# log_manager.rb
require 'fileutils'
require 'logger'
require 'time'

# Define a module for the log management system
module LogManager
  LOG_DIR = './logs'

  # Create log folder based on current day
  def self.create_log_folder
    date_str = Time.now.strftime("%Y-%m-%d")
    daily_folder = File.join(LOG_DIR, date_str)
    FileUtils.mkdir_p(daily_folder) unless File.directory?(daily_folder)
    daily_folder
  end

  # Set up different loggers for each severity level
  def self.setup_loggers
    daily_folder = create_log_folder

    # Define loggers for each severity
    loggers = {
      info: Logger.new(File.join(daily_folder, 'info.log')),
      error: Logger.new(File.join(daily_folder, 'error.log')),
      debug: Logger.new(File.join(daily_folder, 'debug.log'))
    }

    # Set a formatter for all loggers
    loggers.each_value do |logger|
      logger.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime.strftime('%Y-%m-%d %H:%M:%S')} - #{severity}: #{msg}\n"
      end
    end

    loggers
  end
end
