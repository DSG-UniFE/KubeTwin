require 'mqtt'
require 'base64'
require 'json'
require 'yaml'
require 'open3'
require 'fileutils'
require 'securerandom'
require_relative './mqtt_publish'
require_relative './exec_KT'
require_relative './logging_conf'  # Include the logging module

# Constants for MQTT connection
MQTT_HOST = 'localhost'
MQTT_PORT = 1883

# MQTT topics
TOPIC_PUB_TO_FLASK = 'parsing/from-kt'
TOPIC_SUB_LISTEN_FROM_FLASK = 'parsing/to-kt'

# Constants for file paths
FINAL_ALLOCATION_FILE = './final_allocation.txt'
UPLOAD_FOLDER = './uploads/'

# Initialize loggers from LogManager
loggers = LogManager.setup_loggers

# Function to decode and process the message
def process_received_message(message, loggers)
  begin
    decoded_message = JSON.parse(Base64.decode64(message))

    file_name = decoded_message['filename']
    config_data = decoded_message['config']
    yaml_data = decoded_message['yaml']

    # Create the upload directory if it doesn't exist
    FileUtils.mkdir_p(UPLOAD_FOLDER) unless File.directory?(UPLOAD_FOLDER)

    # Generate a random identifier (UUID) to ensure a unique folder name
    random_identifier = SecureRandom.uuid
    folder_name = "#{file_name}_#{random_identifier}"
    subfolder_path = File.join(UPLOAD_FOLDER, folder_name)
    FileUtils.mkdir_p(subfolder_path)

    # Construct file paths within the subfolder
    path_to_save_yaml = File.join(subfolder_path, "#{file_name}.yaml")
    path_to_save_conf = File.join(subfolder_path, "#{file_name}.conf")
    path_to_save_txt = File.join(subfolder_path, "#{file_name}.txt")

    # Write data to files
    write_to_file(path_to_save_yaml, yaml_data, loggers)
    write_to_file(path_to_save_conf, config_data, loggers)

    loggers[:info].info("Files saved: YAML (#{path_to_save_yaml}), CONF (#{path_to_save_conf})")

    # Run KubeTwin to optimize the config file
    exec_KT(path_to_save_conf)

    # Read the optimized config file
    optimized_config_data = read_from_file(FINAL_ALLOCATION_FILE, loggers)

    # Save the optimized config data to a text file
    write_to_file(path_to_save_txt, optimized_config_data, loggers)

    loggers[:info].info("Optimized config data saved to: #{path_to_save_txt}")
    [optimized_config_data, file_name]
  rescue JSON::ParserError => e
    loggers[:error].error("JSON parsing error: #{e.message}")
    nil
  rescue StandardError => e
    loggers[:error].error("An error occurred while processing the message: #{e.message}")
    nil
  end
end

def process_to_send_data(filename, loggers)
  begin
    yaml_data = read_from_file(filename + '.yaml', loggers)
    config_data = read_from_file(filename + '.conf', loggers)
    txt_data = read_from_file(filename + '.txt', loggers)

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
def write_to_file(filename, data, loggers)
  File.open(filename, 'w') { |file| file.write(data) }
  loggers[:info].info("Data written to file: #{filename}")
rescue StandardError => e
  loggers[:error].error("Error writing to file #{filename}: #{e.message}")
end

# Helper function to read data from a file
def read_from_file(filename, loggers)
  File.read(filename)
rescue StandardError => e
  loggers[:error].error("Error reading file #{filename}: #{e.message}")
  nil
end

# MQTT connection and message handling
def mqtt_listen_and_publish(loggers)
  begin
    MQTT::Client.connect(host: MQTT_HOST, port: MQTT_PORT) do |client|
      loggers[:info].info("Connected to the broker...")

      # Subscribe and listen to the topic
      client.get(TOPIC_SUB_LISTEN_FROM_FLASK) do |topic, message|
        loggers[:info].info("Received message on topic #{topic}")

        # Process the message
        optimized_config_data, filename_path = process_received_message(message, loggers)

        if optimized_config_data
          encoded_message = process_to_send_data(filename_path, loggers)
          # Publish the optimized config data back to MQTT
          publish_mqtt_message_from_sub(MQTT_HOST, MQTT_PORT, TOPIC_PUB_TO_FLASK, encoded_message)
        else
          loggers[:error].error("Failed to optimize the config data")
        end
      end
    end
  rescue MQTT::ProtocolException => e
    loggers[:error].error("MQTT protocol error: #{e.message}")
  rescue StandardError => e
    loggers[:error].error("Error in MQTT connection: #{e.message}")
    retry_connection(loggers)
  end
end

# Retry connection with exponential backoff
def retry_connection(loggers, attempts = 5)
  delay = 2
  attempts.times do |i|
    loggers[:warn].warn("Retrying connection in #{delay} seconds... (Attempt #{i + 1}/#{attempts})")
    sleep delay
    begin
      mqtt_listen_and_publish(loggers)
      break
    rescue StandardError => e
      loggers[:error].error("Retry failed: #{e.message}")
      delay *= 2
    end
  end
end

# Main function to start MQTT listening and publishing
mqtt_listen_and_publish(loggers)
