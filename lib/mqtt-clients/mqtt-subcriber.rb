require 'mqtt'
require 'base64'
require 'json'
require 'yaml'
require_relative './mqtt_publish'
require_relative './exec_KT'

require 'open3'

host = 'localhost'
port = 1883
# username = 'user'
# password = 'password'
topic_pub_to_flask = 'parsing/from-kt' # topic to send the optimized config data to the flask server through MQTT
topic_sub_listen_from_flask = 'parsing/to-kt' # topic to listen from flask through MQTT which is the config data parsed from the yaml file
final_allocation_file = './final_allocation.txt'

begin
  # Connect to the MQTT broker
  MQTT::Client.connect(host: 'localhost', port: 1883) do |client| # port: 51883, username: 'user', password: 'password'
    puts "Connected to the broker..."

    # Subscribe to the 'test' topic
    client.get(topic_sub_listen_from_flask) do |topic, message|
      
      # Decode the Base64 string
      decoded_message_base64 = Base64.decode64(message)
      decoded_message_json = JSON.parse(decoded_message_base64)
      puts "Received message on topic #{topic}": #{message}, decoded: #{decoded_message_base64}, json: #{decoded_message_json}"
      
      # Extract the filename, config and yaml data from the JSON message
      file_name = decoded_message_json['filename']
      config_data = decoded_message_json['config']
      yaml_data = decoded_message_json['yaml']

      # Write the config and yaml data to the files
      File.open(file_name+'.yaml', 'w') do |file|
        file.write(yaml_data)
      end

      File.open(file_name+'.conf', 'w') do |file|
        file.write(config_data)
      end

      ##TODO: optimize the config file running KubeTwin

      # Run KubeTwin to optimize the config file
      exec_KT(file_name+'.conf')
      File.open(final_allocation_file, 'r') do |file|
        optimized_config_data = file.read
        puts "Optimized config data: #{optimized_config_data}"
      end

      publish_mqtt_message(host, port, topic_pub_to_flask, config_data_optimized)
    
    end
  end
rescue MQTT::ProtocolException => e
  puts "Failed to connect to the MQTT broker: #{e.message}"
rescue StandardError => e
  puts "An error occurred: #{e.message}"
end

