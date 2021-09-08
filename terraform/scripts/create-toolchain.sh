#!/usr/bin/env bash

#// https://github.com/open-toolchain/sdk/wiki/Toolchain-Creation-page-parameters#headless-toolchain-creation-and-update

# log in using the api key
ibmcloud login --apikey "$API_KEY" -r "$REGION" -g "$RESOURCE_GROUP"

# get the bearer token to create the toolchain instance
IAM_TOKEN="IAM token:  "
BEARER_TOKEN=$(ibmcloud iam oauth-tokens | grep "$IAM_TOKEN" | sed -e "s/^$IAM_TOKEN//")
#echo $BEARER_TOKEN

# prefix region for toolchains
TOOLCHAIN_REGION=$REGION
if [[ ! $TOOLCHAIN_REGION =~ "ibm:" ]]; then
  export TOOLCHAIN_REGION="ibm:yp:$REGION"
fi

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
apikey=$(echo "$credentials" | awk '/apikey/{ print $2 }')

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
response=$(curl -X POST -w "\n%{http_code}" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  -H "Authorization: $iamtoken" \
  -d '{"name": "mobile-simulator", "type": "regularwebapp"}' \
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

printf "\nApp ID instance created and configured"
printf "\nManagement server: $mgmturl"
printf "\nApi key:           $apikey"
printf "\n"

# Create secrets
# Excerpt from example-bank-toolchain script (https://github.com/IBM/example-bank-toolchain/blob/main/scripts/createsecrets.sh)
MGMTEP=$mgmturl
APIKEY=$apikey

response=$(curl -k -v -X POST -w "\n%{http_code}" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -H "Accept: application/json" \
  --data-urlencode "grant_type=urn:ibm:params:oauth:grant-type:apikey" \
  --data-urlencode "apikey=$APIKEY" \
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

# this may not work
oc create secret generic bank-oidc-secret --from-literal=OIDC_JWKENDPOINTURL=$oauthserverurl/publickeys --from-literal=OIDC_ISSUERIDENTIFIER=$oauthserverurl --from-literal=OIDC_AUDIENCES=$clientid

oc create secret generic bank-appid-secret --from-literal=APPID_TENANTID=$tenantid --from-literal=APPID_SERVICE_URL=https://$appidhost

oc create secret generic bank-iam-secret --from-literal=IAM_APIKEY=$APIKEY --from-literal=IAM_SERVICE_URL=https://iam.cloud.ibm.com/identity/token

oc create secret generic mobile-simulator-secrets \
  --from-literal=APP_ID_IAM_APIKEY=$APIKEY \
  --from-literal=APP_ID_MANAGEMENT_URL=$MGMTEP \
  --from-literal=APP_ID_CLIENT_ID=$clientid \
  --from-literal=APP_ID_CLIENT_SECRET=$secret \
  --from-literal=APP_ID_TOKEN_URL=$oauthserverurl \
  --from-literal=PROXY_USER_MICROSERVICE=user-service:9080 \
  --from-literal=PROXY_TRANSACTION_MICROSERVICE=transaction-service:9080

oc create secret generic bank-oidc-adminuser --from-literal=APP_ID_ADMIN_USER=bankadmin --from-literal=APP_ID_ADMIN_PASSWORD=password

oc create secret generic bank-db-secret --from-literal=DB_SERVERNAME=creditdb --from-literal=DB_PORTNUMBER=5432 --from-literal=DB_DATABASENAME=example --from-literal=DB_USER=postgres --from-literal=DB_PASSWORD=postgres

# create the toolchain
PARAMETERS="region_id=$TOOLCHAIN_REGION&resourceGroupId=$RESOURCE_GROUP_ID&autocreate=true"`
`"&repository=$TOOLCHAIN_TEMPLATE_REPO&sourceZipUrl=$APPLICATION_REPO&app_repo=$APPLICATION_REPO&apiKey=$API_KEY"`
`"&registryRegion=$REGION&registryNamespace=$CONTAINER_REGISTRY_NAMESPACE&prodRegion=$REGION"`
`"&prodResourceGroup=$RESOURCE_GROUP&prodClusterName=$CLUSTER_NAME&prodClusterNamespace=$CONTAINER_REGISTRY_NAMESPACE"`
`"&toolchainName=$TOOLCHAIN_NAME&branch=$BRANCH&pipeline_type=$PIPELINE_TYPE"
#echo $PARAMETERS

RESPONSE=$(curl -i -X POST \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Accept: application/json' \
  -H "Authorization: $BEARER_TOKEN" \
  "https://cloud.ibm.com/devops/setup/deploy?env_id=$TOOLCHAIN_REGION&$PARAMETERS")

echo "$RESPONSE"
LOCATION=$(grep location <<<"$RESPONSE" | awk {'print $2'})
echo "View the toolchain at: $LOCATION"

exit 0;
