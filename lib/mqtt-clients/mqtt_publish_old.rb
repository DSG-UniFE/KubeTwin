require 'mqtt'
require 'json'
require 'base64'
require 'digest'
require_relative './log_manager'  # Include the logging module

# Initialize loggers from LogManager
loggers = LogManager.setup_loggers


# Function to encode the message
def encode_message(filename, path_yaml_file, path_optimized_config, path_txt_file, loggers)
  begin
    # Create a JSON object
    message = {
      filename: filename,
      yaml: File.read(path_yaml_file),
      config: File.read(path_optimized_config),
      txt: File.read(path_txt_file)
    }

    loggers[:info].info("Message encoded: #{filename}")

    # Convert the JSON object to a string
    base64_message = Base64.encode64(message.to_json)
    base64_message
  rescue StandardError => e
    loggers[:error].error("Failed to encode message: #{e.message}")
    nil
  end
end

# Function to publish an MQTT message
def publish_mqtt_message(broker_address, port_number, topic, filename, yaml_path_file, kt_path_optimized_config, txt_path_optimized_config, loggers)
  begin
    # Connect to the MQTT broker
    MQTT::Client.connect(host: broker_address, port: port_number) do |client|
      # Encode the message
      encoded_message = encode_message(filename, yaml_path_file, kt_path_optimized_config, txt_path_optimized_config, loggers)

      if encoded_message
        # Publish the message to the specified topic
        client.publish(topic, encoded_message)
        loggers[:info].info("Message published to #{topic}: #{encoded_message}")
      else
        loggers[:error].error("Failed to encode and publish the message.")
      end
    end
  rescue StandardError => e
    loggers[:error].error("Failed to publish message: #{e.message}")
  end
end

# Function to publish an already encoded message
def publish_mqtt_message_from_sub(broker_address, port_number, topic, message, loggers)
  begin
    # Connect to the MQTT broker
    MQTT::Client.connect(host: broker_address, port: port_number) do |client|
      # Publish the message to the specified topic
      client.publish(topic, message)
      # Generate a hash string from the message
      hash_string = Digest::SHA256.hexdigest(message)
      loggers[:info].info("Message published to Topic: #{topic}, Hashed message: #{hash_string}")
    end
  rescue StandardError => e
    loggers[:error].error("Failed to publish message: #{e.message}")
  end
end

# Usage example
broker_address = 'localhost'  # Use your broker address, e.g., 'localhost'
topic = 'parsing/from-kt'
port_number = 1883  # Use the port number your broker is listening on, e.g., 1883
filename = 'tosca_my_solver_3'
yaml_path_file = "#{filename}.yaml"
kt_path_optimized_config = "#{filename}.conf"
txt_path_optimized_config = "#{filename}.txt"

# Call the function to publish a message (just to test the script)
if __FILE__ == $0
  loggers[:info].info("Starting to publish message for #{filename}")
  result = publish_mqtt_message(broker_address, port_number, topic, filename, yaml_path_file, kt_path_optimized_config, txt_path_optimized_config, loggers)

  if result.nil?
    loggers[:error].error("Execution of publishing for #{filename} failed.")
  else
    loggers[:info].info("Execution result: #{result}")
  end
end
