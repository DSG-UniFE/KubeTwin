require 'mqtt'
require 'base64'
require 'json'
require 'yaml'
require 'open3'
require 'fileutils'
require 'securerandom'
require_relative './mqtt_publish'
require_relative './exec_KT'
require_relative './log_manager'  # Include the logging module
require_relative './mqtt_publish'
require_relative 'signals_handler'

# Constants for MQTT connection
MQTT_HOST = 'localhost'
MQTT_PORT = 1883

# MQTT topics
TOPIC_PUB_TO_FLASK = 'parsing/from-kt'
TOPIC_SUB_LISTEN_FROM_FLASK = 'parsing/to-kt'

# Constants for file paths
FINAL_ALLOCATION_FILE = './final_allocation.txt'
UPLOAD_FOLDER = './uploads/'

# Define max attempts for retrying connection
MAX_ATTEMPTS = 50
MAX_SECONDS_TO_RETRY = 60



module MQTTSubscriber
  # Function to decode and process the message with the execution of the oprimization
  def self.process_received_message_and_exec_it(message, loggers)
    begin
      decoded_message = JSON.parse(Base64.decode64(message))

      filename, config_data, yaml_data = decoded_message.values_at('filename', 'config', 'yaml')

      # Create the upload directory if it doesn't exist
      FileUtils.mkdir_p(UPLOAD_FOLDER) unless File.directory?(UPLOAD_FOLDER)

      # Generate a random identifier (UUID) to ensure a unique folder name
      random_identifier = SecureRandom.uuid
      folder_name = "#{filename}_#{random_identifier}"
      subfolder_path = File.join(UPLOAD_FOLDER, folder_name)
      FileUtils.mkdir_p(subfolder_path) # Create the subfolder to save the files with the same name + UUID

      # Construct file paths within the subfolder
      path_to_save_yaml = File.join(subfolder_path, "#{filename}.yaml")
      path_to_save_conf = File.join(subfolder_path, "#{filename}.conf")
      path_to_save_txt = File.join(subfolder_path, "#{filename}.txt")

      # Write data to files
      write_to_file(path_to_save_yaml, yaml_data, loggers)
      write_to_file(path_to_save_conf, config_data, loggers)

      loggers[:info].info("Files saved: YAML (#{path_to_save_yaml}), CONF (#{path_to_save_conf})")

      begin
        # Run KubeTwin to optimize the config file
        ExecKubeTwin.exec_KT(path_to_save_conf, loggers)
      rescue StandardError => e
        loggers[:error].error("An error occurred while running KubeTwin: #{e.message}")
        raise # Re-raise the exception to be handled by the outer rescue block
      end

      # Read the optimized config file
      optimized_config_data = read_from_file(FINAL_ALLOCATION_FILE, loggers)

      # Save the optimized config data to a text file
      write_to_file(path_to_save_txt, optimized_config_data, loggers)

      loggers[:info].info("Optimized config data saved to: #{path_to_save_txt}")
      [optimized_config_data, subfolder_path, filename]
    rescue JSON::ParserError => e
      loggers[:error].error("JSON parsing error: #{e.message}")
      nil
    rescue StandardError => e
      loggers[:error].error("An error occurred while processing the message: #{e.message}")
      nil
    end
  end

  def self.process_to_send_data(subfolder_path, filename, loggers)
    begin
      # Construct file paths within the subfolder
      path_yaml_file = File.join(subfolder_path, "#{filename}.yaml")
      path_conf_file = File.join(subfolder_path, "#{filename}.conf")
      path_txt_file = File.join(subfolder_path, "#{filename}.txt")

      # Read data from files
      yaml_data = read_from_file(path_yaml_file, loggers)
      config_data = read_from_file(path_conf_file, loggers)
      txt_data = read_from_file(path_txt_file, loggers)

      message = {
        filename: filename,
        yaml: yaml_data,
        config: config_data,
        txt: txt_data
      }

      base64_message = Base64.strict_encode64(message.to_json)
      loggers[:info].info("Data processed for sending: #{filename}")
      base64_message
    rescue StandardError => e
      loggers[:error].error("An error occurred while processing the message for sending: #{e.message}")
      nil
    end
  end

  # Helper function to write data to a file
  def self.write_to_file(filename, data, loggers)
    File.open(filename, 'w') { |file| file.write(data) }
    loggers[:info].info("Data written to file: #{filename}")
  rescue StandardError => e
    loggers[:error].error("Error writing to file #{filename}: #{e.message}")
  end

  # Helper function to read data from a file
  def self.read_from_file(filename, loggers)
    File.read(filename)
  rescue StandardError => e
    loggers[:error].error("Error reading file #{filename}: #{e.message}")
    nil
  end

  # MQTT connection and message handling
  def self.mqtt_listen_and_publish(loggers, attempt = 0)
    #SignalsHandler.setup_signal_handler(loggers) # Setup the signal handler for Ctrl+C (SIGINT)
    
    begin
      MQTT::Client.connect(host: MQTT_HOST, port: MQTT_PORT) do |client|
        
        loggers[:info].info("Connected to the broker...")

        # Subscribe and listen to the topic
        client.get(TOPIC_SUB_LISTEN_FROM_FLASK) do |topic, message|
          loggers[:info].info("Received message on topic #{topic}")

          # Process the message
          optimized_config_data, subfolder_path, filename = process_received_message_and_exec_it(message, loggers)

          if optimized_config_data
            encoded_message = process_to_send_data(subfolder_path, filename, loggers)
            # Publish the optimized config data back to MQTT
            MQTTPublisher.publish_mqtt_message_from_sub(MQTT_HOST, MQTT_PORT, TOPIC_PUB_TO_FLASK, encoded_message, loggers)
          else
            loggers[:error].error("Failed to optimize the config data")
          end
        end
      end
    rescue MQTT::ProtocolException => e
      loggers[:error].error("MQTT protocol error: #{e.message}")
      retry_connection(loggers, attempt)
    rescue StandardError => e
      loggers[:error].error("Error in MQTT connection: #{e.message}")
      retry_connection(loggers, attempt)
    end
  end

  # Retry connection with exponential backoff
  def self.retry_connection(loggers, attempt, max_attempts = MAX_ATTEMPTS)
    if attempt >= max_attempts
      loggers[:fatal].fatal("All retry attempts failed. The subcriber is closed definitely.")
      return # Exit if max attempts have been reached
    end

    delay = 2 * (2 ** attempt) # Exponential backoff formula
    return loggers[:warn].warn("Retrying is over #{MAX_SECONDS_TO_RETRY} seconds. The subcriber is closed definitely.") if delay > MAX_SECONDS_TO_RETRY # Limit the delay to 60 seconds maximum although it can be increased thanks to the attempt limit
    loggers[:warn].warn("Retrying connection in #{delay} seconds... (Attempt #{attempt + 1}/#{max_attempts})")
    sleep delay

    begin
      mqtt_listen_and_publish(loggers, attempt + 1) # Increment attempt 
    rescue StandardError => e
      loggers[:error].error("Retry attempt #{attempt + 1} failed: #{e.message}")
      retry_connection(loggers, attempt + 1, max_attempts) # Continue retrying
    end
  end

  
end

# Main function to start MQTT listening and publishing
if __FILE__ == $0
  enable_cli_logging = true # Set this to true to enable CLI logging
  enable_debug_logging = true # Set this to false to disable debug logging
  loggers = LogManager.setup_loggers(enable_cli: enable_cli_logging, enable_debug_log: enable_debug_logging)

  MQTTSubscriber.mqtt_listen_and_publish(loggers)
end
