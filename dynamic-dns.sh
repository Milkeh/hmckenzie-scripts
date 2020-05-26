#!/bin/bash
set +e

#
# README
#
# Configuration for this script requires you to set the required $DOMAIN and $ZONE_ID
# variables.
#
# You can do this by either uncommenting the configuration items below,
# or storing the variables in a 'domain.config' file in the same path as this script.
#

## Configuration. Only uncomment the below lines.
#DOMAIN=
#ZONE_ID=

config="/etc/dynamic-dns/domain.config"

# Source in domain.config file if $DOMAIN hasn't been configured above
if ! [[ -z ${DOMAIN} ]]; then
  echo "Setting domain to ${DOMAIN}"
elif [[ -f ${config} ]]; then
  source ${config}
else
  echo "Domain configuration not set. Exiting."
  exit 1
fi

IP_ADDRESS=$(curl -s icanhazip.com)
ROUTE53_IP=$(aws route53 list-resource-record-sets --hosted-zone-id ${ZONE_ID} \
        | jq -r ".ResourceRecordSets[] | select(.Name == \"${DOMAIN}.\" and .Type == \"A\") | .ResourceRecords[].Value")
JSON_FILE="/tmp/route53_update_dynamic-dns.json"

fn_route53_update()
{
  # Store the Route 53 change as a .JSON file in the path specified in JSON_FILE, and then import it as a part
  # of the ROUTE53_CHANGEID variable. This is later used to check the status of the record update.
  cat > ${JSON_FILE} << EOF
  {
    "Comment": "dynamic-dns script: Update record set to the public IP of this instance",
    "Changes": [
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "${DOMAIN}",
          "Type": "A",
          "TTL": 300,
          "ResourceRecords": [
            {
              "Value": "${IP_ADDRESS}"
            }
          ]
        }
      }
    ]
  }
EOF

  ROUTE53_CHANGEID=$(aws route53 change-resource-record-sets --hosted-zone-id ${ZONE_ID} --change-batch file:///${JSON_FILE} \
  | jq -r .ChangeInfo.Id)
}

fn_route53_check()
{
  # Loop a check of the record update status, using our generated change ID.
  local status=$(aws route53 get-change --id ${ROUTE53_CHANGEID} | jq -r .ChangeInfo.Status)

  echo "Route 53 Change ID is ${ROUTE53_CHANGEID}"
  echo "Record update status is currently: ${status}"

  count=0
  while [[ "${status}" == "PENDING" ]]; do
  count=$(expr ${count} + 1)

    if [[ ${count} -ge 6 ]]; then
      echo "Error: timeout while waiting for record update"
    fi
    sleep 5

    status=$(aws route53 get-change --id ${ROUTE53_CHANGEID} | jq -r .ChangeInfo.Status)
  done

  echo "Record has been updated successfully"
}

# Print variables to the terminal
echo "
Configuration Details:
-------------------
DOMAIN: ${DOMAIN}
HOSTED ZONE ID: ${ZONE_ID}
SERVER IP ADDRESS: ${IP_ADDRESS}
ROUTE 53 IP: ${ROUTE53_IP}

TIME: $(date)
"

if [[ "${IP_ADDRESS}" != "${ROUTE53_IP}" ]]; then
  echo "IP does not match. Updating record in Route 53.."
  fn_route53_update
  echo "Performing status check.."
  fn_route53_check
else
  echo "IP currently up to date"
fi