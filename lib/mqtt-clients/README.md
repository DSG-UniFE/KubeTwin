# MQTT clients to comunicate with the parser server
This is a MQTT client to comunicate with the parser server. It is based on the ruby gem `mqtt`. The project is divided in two parts: the MQTT subcriber client and the MQTT publisher client. The subcriber is responsible to listen to the `parsing/to-kt` topic, process the received data (to optimize) and publish the result bask to the Flask server through the publisher client on the topic `parsing/from-kt`. 

## Usage
Move to the `lib/mqtt-clients` directory and run the following commands:
    
    ```bash
    ruby new-mqtt-sub.rb
    ```

## Data format
The received data format is a JSON object with the following structure encoded in base64:

    ```json
    {
        "filename" : "file_name",
        "yaml" : "data",
        "config" : "data",
    }
    ```
And the published data format is a JSON object with the following structure encoded in base64:

    ```json
    {
        "filename" : "file_name",
        "yaml" : "data",
        "config" : "data",
        "txt" : "data"
    }
    ```
The `txt` field is the result of the processing of the optimization improved by KubeTwin.

## Logging
The client logs the received and published data in the `lib/mqtt-clients/logs` directory. In this directory, there are subdirectories for each day with the logs of that day. The logs are diveded in three files for every criticity level: `info.log`, `debug.log` and `error.log`. Moreover, the logs are stored are printed as-is on the CLI. 

## MQTT clients
At the moment the MQTT client is not configurated without any authentication. This may change in the future in base of the broker configuration.