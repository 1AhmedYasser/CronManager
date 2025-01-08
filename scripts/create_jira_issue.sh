#!/bin/bash
script_name=`basename $0`
pwd
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name started
. constants.ini

get_new_nonce() {
  response=$(curl -s -X POST -H "Content-Type: application/json" "$TRAINING_RESQL/get-new-nonce")
  nonce=$(echo "$response" |grep -Eo "([a-f0-9-]+-){4}[a-f0-9-]+")
  echo "$nonce"
}

sync_res=$(curl -H "x-ruuter-nonce: $(get_new_nonce)" "$CHATBOT_PRIVATE_RUUTER/jira/chats/sync")
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $sync_res

echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name finished