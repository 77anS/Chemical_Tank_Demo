#!/bin/sh

execute_command_until_success(){
  max_attempts="$1"
  shift
  expect_resp="$1"
  shift
  cmd="$@"
  attempts=0
  cmd_status=1
  cmd_resp=""
  until [ $cmd_status -eq 0 ] && [ "$cmd_resp" = "$expect_resp" ]
  do 

    if [ ${attempts} -eq ${max_attempts} ];then
      echo "max attempts reached"
      exit 1
    elif [ ${attempts} -ne 0 ]; then
      sleep 5s
    fi

    cmd_resp=$($cmd)
    cmd_status=$?
    attempts=$(($attempts+1)) 
	
	echo "   cmd_status: $cmd_status, cmd_resp: $cmd_resp, attempts: $attempts"  

  done
  echo "   execute command successfully"
}

echo "Launching Edge Xpert with the required microservices..."
edgexpert up device-modbus device-opc-ua xpert-manager mqtt-broker influxdb grafana nodered

echo "Checking the Metadata Service is running, max retries=10..."
execute_command_until_success 10 200 curl -s -o /dev/null -w "%{http_code}" http://localhost:59881/api/v2/ping

echo "Checking the Modbus Device Service is registered, max retries=10..."
execute_command_until_success 10 200 curl -s -o /dev/null -w "%{http_code}" http://localhost:59881/api/v2/deviceservice/name/device-modbus

echo "Checking the OPC-UA Device Service is registered, max retries=10..."
execute_command_until_success 10 200 curl -s -o /dev/null -w "%{http_code}" http://localhost:59881/api/v2/deviceservice/name/device-opc-ua

echo "Uploading Chemical Tank device profile..."
execute_command_until_success 1 201 curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:59881/api/v2/deviceprofile/uploadfile -F "file=@ChemicalTank.yaml"

echo "Uploading Outlet Valve device profile..."
execute_command_until_success 1 201 curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:59881/api/v2/deviceprofile/uploadfile -F "file=@OutletValve.yaml"

# Note that the payload should not contain any spaces
echo "Onboarding Chemical Tank Device..."
execute_command_until_success 1 207 curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:59881/api/v2/device -H "Content-Type:application/json" -d '[{"apiVersion":"v2","device":{"name":"Chemical-Tank","adminState":"UNLOCKED","operatingState":"UP","protocols":{"modbus-tcp":{"Address":"172.17.0.1","Port":"502","UnitID":"1"}},"serviceName":"device-modbus","protocolName":"modbus-tcp","profileName":"Chemical-Tank","autoEvents":[{"interval":"1s","onChange":false,"sourceName":"Temperature"},{"interval":"1s","onChange":false,"sourceName":"Pressure"},{"interval":"1s","onChange":false,"sourceName":"Level"}]}}]'

echo "Onboarding Outlet Valve Device..."
execute_command_until_success 1 207 curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:59881/api/v2/device -H "Content-Type:application/json" -d '[{"apiVersion":"v2","device":{"name":"Outlet-Valve","adminState":"UNLOCKED","operatingState":"UP","protocols":{"OPC-UA":{"Address":"172.17.0.1:53530/OPCUA/SimulationServer"}},"serviceName":"device-opc-ua","protocolName":"opc-ua","profileName":"Outlet-Valve","autoEvents":[{"interval":"1s","onChange":false,"sourceName":"Setting"}]}}]'

echo "Setting Node-RED flows logic..."
execute_command_until_success 1 204 curl -s -o /dev/null -w "%{http_code}" -X POST http://localhost:1880/flows -H "Content-Type:application/json" --data-binary "@flows.json"

echo "Launching Application Service to export data to MQTT Broker..."
edgexpert up app-service -p nodered-mqtt.toml

echo "Launching Application Service to export data to Influx..."
edgexpert up app-service -p influx.toml

echo "Configuring the Grafana InfluxDB datasource..."
execute_command_until_success 1 200 curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type:application/json" http://admin:admin@localhost:3000/api/datasources -d '{"name":"InfluxDB","type":"influxdb","url":"http://influxdb:8086","access":"proxy","basicAuth":false,"jsonData":{"organization":"my-org","defaultBucket":"my-bucket","version":"Flux"},"secureJsonData":{"token":"custom-token"}}'

echo "Configuring the Grafana dashboard..."
dashboard="Grafana.json"
execute_command_until_success 1 200 curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type:application/json" http://admin:admin@localhost:3000/api/dashboards/db -d '{"dashboard":'"$(cat $dashboard | tr -d '\t\n\r ')"'}'

echo "Launching Application Service to export data to HiveMQ in the Cloud..."
edgexpert up app-service -p hive-mqtt.toml

echo "Chemical Tank Demo Ready"
