#!/bin/bash

printf "\n\033[1;36m## Deleting the previous deployment\033[0m\n"
kubectl delete -f kubernetes/deployment.yml

sleep 45

printf "\n\033[1;36m## Starting the experience\033[0m\n"
start_time=$(date --utc --iso-8601=seconds | sed 's/+00:00/Z/')
ansible-playbook ansible/deploy-app.yaml

printf "\n\033[1;36m## Waiting for the experience to finish\033[0m\n"
sleep 300

while true; do
    desired_replicas=$(kubectl get deployment latency -o=jsonpath='{.spec.replicas}')
    if [ "$desired_replicas" -ge 2 ]; then
        echo "Experience not yet finished, retrying in 1 min"
        sleep 60
    else
        echo "Experience finished"
        break
    fi
done

# Start port forwarding
kubectl port-forward svc/kibana-kb-http 15601:5601 -n elastic &
forward_pid=$!

# Function to stop port forwarding
stop_port_forwarding() {
    kill $forward_pid
}

sleep 1

# Start and get report
ELASTIC_PASSWORD=$(kubectl get secret elastic-cluster-es-elastic-user -o go-template='{{.data.elastic | base64decode}}' -n elastic)
echo "Get password : $ELASTIC_PASSWORD"

# Verify Kibana is ready
echo "Checking Kibana readiness..."
kibana_ready=0
for i in {1..30}; do
    status=$(curl -s -o /dev/null -w "%{http_code}" --insecure https://localhost:15601/login)
    if [ "$status" -eq 200 ]; then
        kibana_ready=1
        break
    fi
    echo "Kibana not ready, retrying in 10 seconds..."
    sleep 10
done

if [ "$kibana_ready" -eq 0 ]; then
    echo "Kibana is not ready after waiting. Exiting."
    stop_port_forwarding
    exit 1
fi

# Verify connection to Elasticsearch
echo "Verifying connection to Elasticsearch..."
curl -u elastic:$ELASTIC_PASSWORD -k https://elastic-cluster-es-http.elastic.svc:9200/_cluster/health

# Create data view
echo "Create or replace data view : Cluster logs"
response_create=$(curl -s --insecure \
-X POST 'https://localhost:15601/api/data_views/data_view' \
--header 'kbn-xsrf: creating' \
--header 'Content-Type: application/json' \
--header "Authorization: Basic $(echo -n "elastic:$ELASTIC_PASSWORD" | base64)" \
--data-raw '{
  "override": true,
  "data_view": {
     "title": "f*",
     "name": "Cluster logs",
     "id": "latency-id",
     "timeFieldName": "@timestamp"
  }
}')

echo "Data view creation response: $response_create"

end_time=$(date --utc --iso-8601=seconds | sed 's/+00:00/Z/')

encoded_start_time=$(echo "$start_time" | sed 's/:/%3A/g')
encoded_end_time=$(echo "$end_time" | sed 's/:/%3A/g')

# Execute POST request to start the report on the last 10 minutes
echo "Request reporting"
response_post=$(curl --insecure \
 -H "Authorization: Basic $(echo -n "elastic:$ELASTIC_PASSWORD" | base64)" \
 -H "kbn-xsrf: reporting" \
 -X POST \
 "https://localhost:15601/api/reporting/generate/csv_searchsource?jobParams=%28browserTimezone%3AEurope%2FParis%2Ccolumns%3A%21%28%27%40timestamp%27%2Cmessage%2Ckubernetes.pod.name%29%2CobjectType%3Asearch%2CsearchSource%3A%28fields%3A%21%28%28field%3A%27%40timestamp%27%2Cinclude_unmapped%3Atrue%29%2C%28field%3Amessage%2Cinclude_unmapped%3Atrue%29%2C%28field%3Akubernetes.pod.name%2Cinclude_unmapped%3Atrue%29%29%2Cfilter%3A%21%28%28meta%3A%28field%3A%27%40timestamp%27%2Cindex%3Alatency-id%2Cparams%3A%28%29%29%2Cquery%3A%28range%3A%28%27%40timestamp%27%3A%28format%3Astrict_date_optional_time%2Cgte%3A%27$encoded_start_time%27%2Clte%3A%27$encoded_end_time%27%29%29%29%29%29%2Cindex%3Alatency-id%2Cparent%3A%28filter%3A%21%28%29%2Cindex%3Alatency-id%2Cquery%3A%28language%3Akuery%2Cquery%3A%27%27%29%29%2Csort%3A%21%28%28%27%40timestamp%27%3Aasc%29%29%2CtrackTotalHits%3A%21t%29%2Ctitle%3A%27Latency%20logs%20report%27%2Cversion%3A%278.6.2%27%29")

echo "Reporting request response: $response_post"

# Extract the path from the response
url=$(echo "$response_post" | jq -r '.path')
echo "Path to get report: $url"

# Delete existing file
rm -f python/input/result.csv

logs_file="python/input/result.csv"

# Loop until the response is different from "wait"
while true; do
    # Execute GET request to get the report
    curl --insecure -H "Authorization: Basic $(echo -n "elastic:$ELASTIC_PASSWORD" | base64)" "https://localhost:15601$url" -o "$logs_file" -s
    
    # Verify if the response is different from "processing"
    if grep -q -v -e "pending" -e "processing" "$logs_file"; then
        echo "Logs saved in $logs_file"
        break
    else
        echo "Still processing, retrying in 1 min"
    fi
    
    # Sleep for 1 minute
    sleep 60
done

# Stop port forwarding
stop_port_forwarding

# Execute a Python script to process the result.csv file
printf "\n\033[1;36m## Executing process_output.py\033[0m\n"
python3 scripts/process_output.py python/input/result.csv
# Execute the python script
printf "\n\033[1;36m## Executing main.py\033[0m\n"
python3 python/main.py
printf "\n\033[1;36m## Executing cdf.py\033[0m\n"
python3 python/cdf.py

printf "\n\033[1;36m## Executing extract.py\033[0m\n"
python3 scripts/extract.py

printf "\n\033[1;36m## Results are available in the python/output folder\033[0m\n"
