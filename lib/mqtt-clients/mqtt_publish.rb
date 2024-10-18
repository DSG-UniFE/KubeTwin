require 'mqtt'
require 'json'
require 'base64'


def encode_message(filename, path_yaml_file, path_optimized_config, path_txt_file)
    # Create a JSON object
    message = {
      filename: filename,
      yaml: File.read(path_yaml_file),
      config: File.read(path_optimized_config),
      txt: File.read(path_txt_file)
    }
    # Convert the JSON object to a string
    message = message.to_json
    base64_message = Base64.encode64(message)
    base64_message
end


# Define a function to publish an MQTT message
def publish_mqtt_message(broker_address, port_number, topic, filename, yaml_path_file, kt_path_optimized_config, txt_path_optimized_config)
    begin
      # Connect to the MQTT broker
      MQTT::Client.connect(host: broker_address, port: port_number) do |client|

        # Encode the message
        encoded_message = encode_message(filename, yaml_path_file, kt_path_optimized_config, txt_path_optimized_config)
        # Publish the message to the specified topic
        client.publish(topic, encoded_message)
        puts "Message published to #{topic}: #{encoded_message}"
      end
    rescue => e
      puts "Failed to publish message: #{e.message}"
    end
  end

def publish_mqtt_message_from_sub(broker_address, port_number, topic, message)
    # the messagge is already encoded in base64 format and it was a json object before 
    # json object: {filename: filename, yaml: yaml_data, config: config_data, txt: txt_data}
    begin
      # Connect to the MQTT broker
      MQTT::Client.connect(host: broker_address, port: port_number) do |client|
        # Publish the message to the specified topic
        client.publish(topic, message)
        puts "Message published to #{topic}: #{message}"
      end
    rescue => e
      puts "Failed to publish message: #{e.message}"
    end
  end

# Usage example
broker_address = 'localhost'  # Use your broker address, e.g., 'localhost'
topic = 'parsing/from-kt'
message = 'Hello from Ruby MQTT publisher!'
port_number = 1883  # Use the port number your broker is listening on, e.g., 1883
filename = 'tosca_my_solver_3'
yaml_path_file = filename+'.yaml'
kt_path_optimized_config = filename+'.conf'
txt_path_optimized_config = filename+'.txt'

# Call the function to publish a message (just to test the script)
if __FILE__ == $0
  result = publish_mqtt_message(broker_address, port_number, topic, filename, yaml_path_file, kt_path_optimized_config, txt_path_optimized_config)

  if result.nil?
    puts "Execution of #{conf_filename} failed."
  else
    puts "Execution result:\n#{result}"
  end
end
