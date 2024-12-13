#!/bin/bash

script_name=`basename $0`
pwd
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name started
. constants.ini

get_new_nonce() {
  response=$(curl -s -X POST -H "Content-Type: application/json" "$CHATBOT_BOT_RESQL/get-new-nonce")
  nonce=$(echo "$response" |grep -Eo "([a-f0-9-]+-){4}[a-f0-9-]+")
  echo "$nonce"
}


deleted_res=$(curl -H "x-ruuter-nonce: $(get_new_nonce)" -H "Content-Type: application/json" "$CHATBOT_RUUTER_PRIVATE/cron-tasks/delete-conversations?isAuth=true")
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $deleted_res

echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name finished