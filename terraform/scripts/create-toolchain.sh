#!/usr/bin/env bash

#// https://github.com/open-toolchain/sdk/wiki/Toolchain-Creation-page-parameters#headless-toolchain-creation-and-update

# log in using the api key
ibmcloud login --apikey "$API_KEY" -r "$REGION" -g "$RESOURCE_GROUP"

# get the bearer token to create the toolchain instance
IAM_TOKEN="IAM token:  "
BEARER_TOKEN=$(ibmcloud iam oauth-tokens | grep "$IAM_TOKEN" | sed -e "s/^$IAM_TOKEN//")
#echo $BEARER_TOKEN

RESOURCE_GROUP_ID=$(ibmcloud resource group $RESOURCE_GROUP --output JSON | jq ".[].id" -r)

# Create AppID service instance
# Excerpt from example-bank-toolchain script (https://github.com/IBM/example-bank-toolchain/blob/main/scripts/createappid.sh)
ibmcloud resource service-instance appid-example-bank
if [ "$?" -ne "0" ]; then
  echo "Creating the 'appid-example-bank' service..."
  ibmcloud resource service-instance-create appid-example-bank appid graduated-tier us-south
else
  echo "The 'appid-example-bank' service already exists"
fi

ibmcloud resource service-key appid-example-bank-credentials
if [ "$?" -ne "0" ]; then
  echo "Creating the 'appid-example-bank-credentials' service key..."
  ibmcloud resource service-key-create appid-example-bank-credentials Writer --instance-name appid-example-bank
else
  echo "The 'appid-example-bank-credentials' service key already exists"
fi

credentials=$(ibmcloud resource service-key appid-example-bank-credentials)

mgmturl=$(echo "$credentials" | awk '/managementUrl/{ print $2 }')
appid_apikey=$(echo "$credentials" | awk '/apikey:/{ print $2 }')

iamtoken=$(ibmcloud iam oauth-tokens | awk '/IAM/{ print $3" "$4 }')

printf "\nSetting cloud directory options\n"
response=$(curl -X PUT -w "\n%{http_code}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: $iamtoken" \
  -d '{
       "isActive":true,
       "config":
       {
           "selfServiceEnabled":true,
           "interactions":
           {
               "identityConfirmation":
               {
                   "accessMode":"OFF",
                   "methods":    ["email"]
               },
               "welcomeEnabled":true,
               "resetPasswordEnabled":true,
               "resetPasswordNotificationEnable":true
           },
           "signupEnabled":true,
           "identityField":"userName"
       }
     }' \
  "${mgmturl}/config/idps/cloud_directory")

echo $response

code=$(echo "${response}" | tail -n1)
[ "$code" -ne "200" ] && printf "\nFAILED to set cloud directory options\n" && exit 1

printf "\nCreating application\n"
APP_PARAMS=$( jq -n \
  --arg ms "$MOBILE_SIM" \
  '{name: $ms, type: "regularwebapp"}' )
response=$(curl -X POST -w "\n%{http_code}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: $iamtoken" \
  -d "$APP_PARAMS" \
  "${mgmturl}/applications")

echo $response

code=$(echo "${response}" | tail -n1)
[ "$code" -ne "200" ] && printf "\nFAILED to create application\n" && exit 1

clientid=$(echo "${response}" | head -n1 | jq -j '.clientId')

printf "\nDefining admin scope\n"
response=$(curl -X PUT -w "\n%{http_code}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: $iamtoken" \
  -d '{"scopes": ["admin"]}' \
  "${mgmturl}/applications/$clientid/scopes")

echo $response

code=$(echo "${response}" | tail -n1)
[ "$code" -ne "200" ] && printf "\nFAILED to define admin scope\n" && exit 1

printf "\nDefining admin role\n"
response=$(curl -X POST -w "\n%{http_code}"  \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: $iamtoken" \
  -d '{"name": "admin",
       "access": [ {"application_id": "'$clientid'", "scopes": [ "admin" ]} ]
     }' \
  "${mgmturl}/roles")

echo $response

code=$(echo "${response}" | tail -n1)
[ "$code" -ne "201" ] && printf "\nFAILED to define admin role\n" && exit 1

roleid=$(echo "${response}" | head -n1 | jq -j '.id')

printf "\nDefining admin user in cloud directory\n"
response=$(curl -X POST -w "\n%{http_code}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: $iamtoken" \
  -d '{"emails": [
          {"value": "bankadmin@yopmail.com","primary": true}
        ],
       "userName": "bankadmin",
       "password": "password"
      }' \
  "${mgmturl}/cloud_directory/sign_up?shouldCreateProfile=true")

echo $response

code=$(echo "${response}" | tail -n1)
[ "$code" -ne "201" ] && printf "\nFAILED to define admin user in cloud directory\n" && exit 1

printf "\nGetting admin user profile\n"
response=$(curl -X GET -w "\n%{http_code}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: $iamtoken" \
  "${mgmturl}/users?email=bankadmin@yopmail.com&dataScope=index")

echo $response

code=$(echo "${response}" | tail -n1)
[ "$code" -ne "200" ] && printf "\nFAILED to get admin user profile\n" && exit 1

userid=$(echo "${response}" | head -n1 | jq -j '.users[0].id')

printf "\nAdding admin role to admin user\n"
response=$(curl -X PUT -w "\n%{http_code}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: $iamtoken" \
  -d '{"roles": { "ids": ["'$roleid'"]}}' \
  "${mgmturl}/users/$userid/roles")

echo $response

code=$(echo "${response}" | tail -n1)
[ "$code" -ne "200" ] && printf "\nFAILED to add admin role to admin user\n" && exit 1

#printf "\nApp ID instance created and configured"
#printf "\nManagement server: $mgmturl"
#printf "\nApi key:           $appid_apikey"
#printf "\n"

# Create secrets
# Excerpt from example-bank-toolchain script (https://github.com/IBM/example-bank-toolchain/blob/main/scripts/createsecrets.sh)
MGMTEP=$mgmturl
APPID_APIKEY=$appid_apikey

response=$(curl -k -v -X POST -w "\n%{http_code}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json" \
  --data-urlencode "grant_type=urn:ibm:params:oauth:grant-type:apikey" \
  --data-urlencode "apikey=$APPID_APIKEY" \
  "https://iam.cloud.ibm.com/identity/token")

echo $response

code=$(echo "${response}" | tail -n1)
[ "$code" -ne "200" ] && exit 1

accesstoken=$(echo "${response}" | head -n1 | jq -j '.access_token')

response=$(curl -v -X GET -w "\n%{http_code}" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $accesstoken" \
  $MGMTEP/applications)

echo $response

code=$(echo "${response}" | tail -n1)
[ "$code" -ne "200" ] && exit 1

tenantid=$(echo "${response}"| head -n1 | jq -j '.applications[0].tenantId')
clientid=$(echo "${response}"| head -n1 | jq -j '.applications[0].clientId')
secret=$(echo "${response}"| head -n1 | jq -j '.applications[0].secret')
oauthserverurl=$(echo "${response}"| head -n1 | jq -j '.applications[0].oAuthServerUrl')
appidhost=$(echo "${oauthserverurl}" | awk -F/ '{print $3}')

# Install OpenShift CLI
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.6.42/openshift-client-linux-4.6.42.tar.gz
tar -xvf openshift-client-linux-4.6.42.tar.gz
oc version
ibmcloud plugin update --all
ibmcloud oc cluster config -c $CLUSTER_NAME --admin
sleep 10  # Waiting 10 seconds for configuration to be established
echo "Creating new project 'example-bank'..."
oc new-project example-bank

# Create OC secrets
echo "Creating secrets..."
oc create secret generic bank-oidc-secret --from-literal=OIDC_JWKENDPOINTURL=$oauthserverurl/publickeys --from-literal=OIDC_ISSUERIDENTIFIER=$oauthserverurl --from-literal=OIDC_AUDIENCES=$clientid
oc create secret generic bank-appid-secret --from-literal=APPID_TENANTID=$tenantid --from-literal=APPID_SERVICE_URL=https://$appidhost
oc create secret generic bank-iam-secret --from-literal=IAM_APIKEY=$APPID_APIKEY --from-literal=IAM_SERVICE_URL=https://iam.cloud.ibm.com/identity/token
oc create secret generic mobile-simulator-secrets \
  --from-literal=APP_ID_IAM_APIKEY=$APPID_APIKEY \
  --from-literal=APP_ID_MANAGEMENT_URL=$MGMTEP \
  --from-literal=APP_ID_CLIENT_ID=$clientid \
  --from-literal=APP_ID_CLIENT_SECRET=$secret \
  --from-literal=APP_ID_TOKEN_URL=$oauthserverurl \
  --from-literal=PROXY_USER_MICROSERVICE=user-service:9080 \
  --from-literal=PROXY_TRANSACTION_MICROSERVICE=transaction-service:9080
oc create secret generic bank-oidc-adminuser --from-literal=APP_ID_ADMIN_USER=bankadmin --from-literal=APP_ID_ADMIN_PASSWORD=password
oc create secret generic bank-db-secret --from-literal=DB_SERVERNAME=creditdb --from-literal=DB_PORTNUMBER=5432 --from-literal=DB_DATABASENAME=example --from-literal=DB_USER=postgres --from-literal=DB_PASSWORD=postgres

# create the operator group
echo "Creating the OperatorGroup 'bank-postgresql'..."
oc apply -f scripts/operatorgroup.yaml

# create the subscription
echo "Creating the Subscription 'bank-subscription'..."
oc apply -f scripts/sub.yaml

echo "Waiting for PostgreSQL Operator to be created..."
sleep 30
WAIT=300
COUNTER=0
while [ $COUNTER -lt $WAIT ]; do
  OG_STATUS=$(oc get pods | grep postgresql-operator | awk {'print $3'})
  if [[ $OG_STATUS == "Running" ]];then
    echo "OG Status: $OG_STATUS"
    break
  else
    COUNTER=$((COUNTER+30))
    echo "OG Status: $OG_STATUS"
    if [[ $COUNTER == $WAIT ]];then
      echo "Operator took longer than 5 minutes to create. This could be a problem."
      break
    fi
    echo "Trying again in 30 seconds..."
    sleep 30
  fi
done

# create the database
echo "Creating the PostgreSQL database 'creditdb'..."
oc apply -f scripts/db.yaml

echo "Waiting for PostgreSQL database to be created..."
sleep 30
WAIT=300
COUNTER=0
while [ $COUNTER -lt $WAIT ]; do
  DB_STATUS=$(oc get pods | grep creditdb | awk {'print $3'})
  if [[ $DB_STATUS == "Running" ]];then
    echo "DB Status: $DB_STATUS"
    break
  else
    COUNTER=$((COUNTER+30))
    echo "DB Status: $DB_STATUS"
    if [[ $COUNTER == $WAIT ]];then
      echo "DB took longer than 4 minutes to create. This could be a problem."
      break
    fi
    echo "Trying again in 30 seconds..."
    sleep 30
  fi
done

# connect to database
echo "Connecting to the 'creditdb' database..."
oc expose deploy creditdb --port=5432 --target-port=5432 --type=LoadBalancer --name my-pg-svc
oc get svc
oc get secrets

# create job
echo "Creating the job 'cc-schema-load'..."
oc apply -f scripts/job.yaml
echo "Waiting 60 seconds for job to complete..."
sleep 60
oc get jobs
oc get pods

# check for the existence of the Secrets Manager instance
SM_FOUND=$(ibmcloud resource service-instances | grep "$SM_SERVICE_NAME")
if [[ $SM_FOUND ]]; then
  echo "Secrets Manager '$SM_SERVICE_NAME' already exists."
else
  echo "Secrets Manager '$SM_SERVICE_NAME' does not exist."
  echo "Creating Secrets Manager service now..."
  # NOTE: Secrets Manager service can take approx 5-8 minutes to provision
  ibmcloud resource service-instance-create $SM_SERVICE_NAME secrets-manager lite $REGION
  wait_secs=600
  count=0
  sleep_time=60
  wait_mins=$(($wait_secs / $sleep_time))
  echo "Waiting up to $wait_mins minutes for Secrets Manager service to provision..."
  while [[ $count -le $wait_secs ]]; do
    ibmcloud resource service-instances >services.txt
    secretLine=$(cat services.txt | grep $SM_SERVICE_NAME)
    stringArray=($secretLine)
    if [[ "${stringArray[2]}" != "active" ]]; then
      echo "Secrets Manager status: ${stringArray[2]}"
      count=$(($count + $sleep_time))
      if [[ $count -gt $wait_secs ]]; then
        echo "Secrets Manager service took longer than $wait_mins minutes to provision."
        echo "You might have to re-configure this integration in the toolchain once the service finally provisions."
      else
        echo "Waiting $sleep_time seconds to check again..."
        sleep $sleep_time
      fi
    else
      echo "Secrets Manager successfully provisioned"
      echo "Status: ${stringArray[2]}"
      break
    fi
  done
fi

# generate gpg key
gpg --batch --pinentry-mode loopback --generate-key <<EOF
%no-protection
Key-Type: 1
Key-Length: 2048
Subkey-Type: 1
Subkey-Length: 2048
Name-Real: Root User
Name-Email: root@cipipeline.ibm.com
Expire-Date: 0
EOF
export GPG_SECRET=$(gpg --export-secret-key root@cipipeline.ibm.com  | base64)
gpg --export-secret-key root@cipipeline.ibm.com  | base64 > privatekey.txt

# get secrets manager instance id
IN=$(ibmcloud resource service-instance "$SM_SERVICE_NAME" | grep crn)
IFS=':' read -ra ADDR <<< "$IN"
SM_INSTANCE_ID="${ADDR[8]}"

# get secrets data for API, GPG, and COS API keys
SECRETS_NAMES=("IAM_API_Key" "GPG_Key" "COS_API_Key")
SECRETS_PAYLOADS=("$API_KEY" "$GPG_SECRET" "$COS_API_KEY")

# loop through secrets names and create secrets for each in the secrets manager
for i in ${!SECRETS_NAMES[@]}; do
  echo "Creating Arbitrary secret for ${SECRETS_NAMES[$i]} in $SM_SERVICE_NAME..."
  REQUEST_BODY=$( jq -n \
    --arg sn "${SECRETS_NAMES[$i]}" \
    --arg sp "${SECRETS_PAYLOADS[$i]}" \
    '{metadata: {collection_type: "application/vnd.ibm.secrets-manager.secret+json", collection_total: 1}, resources: [{name: $sn, payload: $sp}]}' )
  RESPONSE=$(curl --write-out '%{http_code}' --silent --output /dev/null -i -X POST \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -H "Authorization: $BEARER_TOKEN" \
    -d "$REQUEST_BODY" \
    "https://$SM_INSTANCE_ID.$REGION.secrets-manager.appdomain.cloud/api/v1/secrets/arbitrary")
  if [[ "$RESPONSE" =~ ^2 ]]; then
    echo "The secret was successfully created."
  else
    echo "The secret failed to be created."
    case $RESPONSE in
      400)
        echo "Status Code: 400 Bad Request"
	      ;;
      401)
        echo "Status Code: 401 Unauthorized"
	      ;;
      403)
        echo "Status Code: 403 Forbidden"
	      ;;
      409)
        echo "Status Code: 409 Secret Already Exists"
	      ;;
      429)
        echo "Status Code: 429 Too Many Requests"
	      ;;
      *)
	      echo "Status Code: $RESPONSE Unknown"
	      ;;
    esac
  fi
done

export TOOLCHAIN_REGION="ibm:yp:$REGION"
# URL encode CI_TOOLCHAIN_REPO, CD_TOOLCHAIN_REPO, and APPLICATION_REPO
export CI_TOOLCHAIN_REPO=$(echo "$CI_TOOLCHAIN_REPO" | jq -Rr @uri)
export CD_TOOLCHAIN_REPO=$(echo "$CD_TOOLCHAIN_REPO" | jq -Rr @uri)
export APPLICATION_REPO=$(echo "$APPLICATION_REPO" | jq -Rr @uri)
export appName=$APP_NAME

# create the ci toolchain
echo "Creating the CI Toolchain..."
PARAMETERS="autocreate=true&appName=$APP_NAME&apiKey={vault::$SM_NAME.Default.API_Key}"`
`"&repository=$CI_TOOLCHAIN_REPO&repository_token=$GITLAB_TOKEN&branch=$BRANCH"`
`"&sourceRepoUrl=$APPLICATION_REPO&resourceGroupId=$RESOURCE_GROUP_ID"`
`"&registryRegion=$TOOLCHAIN_REGION&registryNamespace=$CONTAINER_REGISTRY_NAMESPACE&devRegion=$REGION"`
`"&devResourceGroup=$RESOURCE_GROUP&devClusterName=$CLUSTER_NAME&devClusterNamespace=$CLUSTER_NAMESPACE"`
`"&prodResourceGroup=$RESOURCE_GROUP&prodClusterName=$CLUSTER_NAME&prodRegion=$REGION&prodClusterNamespace=$CLUSTER_NAMESPACE"`
`"&toolchainName=$CI_TOOLCHAIN_NAME&pipeline_type=$PIPELINE_TYPE&pipelineConfigBranch=$PIPELINE_CONFIG_BRANCH&gitToken=$GITLAB_TOKEN"`
`"&cosBucketName=$COS_BUCKET_NAME&cosEndpoint=$COS_URL&cosApiKey={vault::$SM_NAME.Default.COS_Key}&vaultSecret={vault::$SM_NAME.Default.GPG_Key}"`
`"&smName=$SM_NAME&smRegion=$TOOLCHAIN_REGION&smResourceGroup=$RESOURCE_GROUP&smInstanceName=$SM_SERVICE_NAME"
echo $PARAMETERS

RESPONSE=$(curl -i -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Accept: application/json' \
  -H "Authorization: $BEARER_TOKEN" \
  -d "$PARAMETERS" \
  "https://cloud.ibm.com/devops/setup/deploy?env_id=$TOOLCHAIN_REGION")

echo "$RESPONSE"
LOCATION=$(grep location <<<"$RESPONSE" | awk {'print $2'})
echo "View the CI toolchain at: $LOCATION"

# get data from newly created ci toolchain
# URL might need "?include=services,unconfigured" added to the end
# "${LOCATION}?include=services,unconfigured" instead of "$LOCATION"
TOOLCHAIN_ID=$(echo "$LOCATION" | cut -d '/' -f 6 | cut -d '?' -f 1)
echo "Waiting 10 seconds for services within the CI Toolchain to be configured..."
sleep 10
echo "Gathering data from the CI Toolchain..."
RESPONSE=$(curl -s \
  -H 'Accept: application/json' \
  -H "Authorization: $BEARER_TOKEN" \
  "${LOCATION%$'\r'}?include=services,unconfigured")

# parse the json to obtain the evidence, inventory, and issues repo URLs
SERVICES=$(echo $RESPONSE | jq -r '.services | length')
count=0
while [[ $count -lt $SERVICES ]]; do
	service=$(echo $RESPONSE | jq -r --argjson count $count '.services[$count] .service_id')
	if [[ "$service" == "hostedgit" ]]; then
		if [[ $(echo $RESPONSE | jq --argjson count $count '.services[$count] .parameters.repo_url') == *'inventory'* ]]; then
			INV_URL=$(echo $RESPONSE | jq -r --argjson count $count '.services[$count] .parameters.repo_url')
		elif [[ $(echo $RESPONSE | jq --argjson count $count '.services[$count] .parameters.repo_url') == *'evidence'* ]]; then
			EVI_URL=$(echo $RESPONSE | jq -r --argjson count $count '.services[$count] .parameters.repo_url')
		elif [[ $(echo $RESPONSE | jq --argjson count $count '.services[$count] .parameters.repo_url') == *'issues'* ]]; then
			ISS_URL=$(echo $RESPONSE | jq -r --argjson count $count '.services[$count] .parameters.repo_url')
		fi
	fi
	((count++))
done

echo "Inventory URL: ${INV_URL%.*}"
echo "Evidence URL: ${EVI_URL%.*}"
echo "Issues URL: ${ISS_URL%.*}"

# url encode a few values
export ISSUES_REPO=$(echo "${ISS_URL%.*}" | jq -Rr @uri)
export EVIDENCE_REPO=$(echo "${EVI_URL%.*}" | jq -Rr @uri)
export INVENTORY_REPO=$(echo "${INV_URL%.*}" | jq -Rr @uri)

# create the cd toolchain
echo "Creating the CD Toolchain..."
PARAMETERS="autocreate=true&appName=$APP_NAME&ibmCloudApiKey={vault::$SM_NAME.Default.API_Key}"`
`"&repository=$CD_TOOLCHAIN_REPO&repository_token=$GITLAB_TOKEN&branch=$BRANCH"`
`"&pipelineConfig=$APPLICATION_REPO&resourceGroupId=$RESOURCE_GROUP_ID"`
`"&registryRegion=$TOOLCHAIN_REGION&registryNamespace=$CONTAINER_REGISTRY_NAMESPACE&clusterRegion=$REGION"`
`"&clusterResourceGroup=$RESOURCE_GROUP&clusterName=$CLUSTER_NAME&clusterNamespace=$CLUSTER_NAMESPACE"`
`"&toolchainName=$CD_TOOLCHAIN_NAME&pipeline_type=$PIPELINE_TYPE&pipelineConfigBranch=$PIPELINE_CONFIG_BRANCH&gitToken=$GITLAB_TOKEN"`
`"&cosBucketName=$COS_BUCKET_NAME&cosEndpoint=$COS_URL&cosApiKey={vault::$SM_NAME.Default.COS_Key}&vaultSecret={vault::$SM_NAME.Default.GPG_Key}"`
`"&smName=$SM_NAME&smRegion=$TOOLCHAIN_REGION&smResourceGroup=$RESOURCE_GROUP&smInstanceName=$SM_SERVICE_NAME&doiToolchainId=$TOOLCHAIN_ID"`
`"&incidentIssuesRepo=$ISSUES_REPO&evidenceLockerRepo=$EVIDENCE_REPO&inventoryRepo=$INVENTORY_REPO"
echo $PARAMETERS

RESPONSE=$(curl -i -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Accept: application/json' \
  -H "Authorization: $BEARER_TOKEN" \
  -d "$PARAMETERS" \
  "https://cloud.ibm.com/devops/setup/deploy?env_id=$TOOLCHAIN_REGION")

echo "$RESPONSE"
LOCATION=$(grep location <<<"$RESPONSE" | awk {'print $2'})
echo "View the CD toolchain at: $LOCATION"

exit 0;
