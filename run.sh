#!/bin/bash -eu
set -o pipefail

VN_TOTAL=300
VN_PER_APPLY=75

check_env() {
  if [ -z "$APSTRA_URL" ]; then
    echo "APSTRA_URL must be set in the environment"
    exit 1
  fi

  if [ -z "$APSTRA_USER" ]; then
    echo "APSTRA_USER must be set in the environment"
    exit 1
  fi

  if [ -z "$APSTRA_PASS" ]; then
    echo "APSTRA_PASS must be set in the environment"
    exit 1
  fi
}

get_token() {
  local URL
  local CURL

  URL="${APSTRA_URL}/api/aaa"
  CURL=$(curl -sk "${URL}/login" -d "{\"username\": \"$APSTRA_USER\", \"password\": \"$APSTRA_PASS\"}" -H "Content-Type: application/json")
  TOKEN=$(jq -r .token <<< "$CURL")
}

update_task_status() {
  local BLUEPRINT_ID
  local URL
  local NEW_TASK_STATUS
  local MERGED

  BLUEPRINT_ID=$(jq -r ".outputs.blueprint_id.value" < terraform.tfstate)
  URL="${APSTRA_URL}/api/blueprints/${BLUEPRINT_ID}/tasks"
  NEW_TASK_STATUS=$(curl -skX GET "$URL" -H "Content-Type: application/json" -H "AUTHTOKEN: ${TOKEN}" | jq '.items | map( { (.id|tostring): . } ) | add')
  MERGED=$(jq -s add <<< "$TASK_STATUS $NEW_TASK_STATUS")
  TASK_STATUS="$MERGED"
}

parse_date_to_epoch() {
  local NO_TZ
  local EPOCH

  NO_TZ=${1//+*/} # drop the timezone
  EPOCH=$(date -jf '%Y-%m-%dT%H:%M:%S' +'%s' "${NO_TZ//.*}")
  echo "$EPOCH.${NO_TZ//*.}"
}


export SSLKEYLOGFILE=~/.tls.log
check_env
get_token

TASK_STATUS="{}"
TF_OPTS=(--auto-approve --refresh=false --input=false)
export TF_IN_AUTOMATION=1
export TF_VAR_vn_count=0

while [ $TF_VAR_vn_count -lt $VN_TOTAL ]
do
  TF_VAR_vn_count=$((TF_VAR_vn_count + VN_PER_APPLY))
  if [ $TF_VAR_vn_count -gt $VN_TOTAL ]
  then
    TF_VAR_vn_count=$VN_TOTAL
  fi

  terraform apply "${TF_OPTS[@]}"
  update_task_status
#  TASK_STATUS_COUNT=$(jq 'to_entries | map(select(.value.type=="blueprint.facade.POST./virtual-networks")) | from_entries | length' <<< "$TASK_STATUS")
#  echo ">>>>>>>>>>>>>>>>>>>>> $TASK_STATUS_COUNT TASKS <<<<<<<<<<<<<<<<<<<<<<"
done

VN_TASKS=$(jq 'to_entries | map(select(.value.type=="blueprint.facade.POST./virtual-networks")) | from_entries' <<< "$TASK_STATUS")
echo "$VN_TASKS" | jq
TASK_IDS=$(jq -r 'keys[]' <<< "$VN_TASKS")

echo "id,created_at,begin_at,last_updated_at"
for TASK_ID in $TASK_IDS
do
  TASK=$(jq ".[\"$TASK_ID\"]" <<< "$VN_TASKS")
#  echo "${TASK_ID},$(jq '.created_at' <<< "$TASK"),$(jq '.begin_at' <<< "$TASK"),$(jq '.last_updated_at' <<< "$TASK"),"
  EPOCH_CREATE=$(parse_date_to_epoch "$(jq -r '.created_at' <<< "$TASK")")
  EPOCH_BEGIN=$(parse_date_to_epoch "$(jq -r '.begin_at' <<< "$TASK")")
  EPOCH_LAST_UPDATE=$(parse_date_to_epoch "$(jq -r '.last_updated_at' <<< "$TASK")")
  echo "${TASK_ID},${EPOCH_CREATE},${EPOCH_BEGIN},${EPOCH_LAST_UPDATE}"
done



#"created_at":     	"2023-12-08T02:05:51.917881+0000",
#"begin_at":        	"2023-12-08T02:05:53.446680+0000",
#"last_updated_at":	"2023-12-08T02:05:54.114378+0000",

