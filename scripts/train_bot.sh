#!/bin/bash
script_name=`basename $0`
pwd
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name started
. constants.ini

# POST request to merge training yaml files
curl -X POST -H "Content-Type: application/json" -d '{"file_path":"'$TRAINING_FILES_PATH'"}' "$TRAINING_DMAPPER/mergeYaml" > temp

checksum=$(curl -X POST -H "Content-Type: text/plain" --data-binary @temp "$TRAINING_DMAPPER/utils/calculate-sha256-checksum")

resql_response=$(curl -X POST -H "Content-Type: application/json" "$TRAINING_RESQL/get-latest-ready-model")
if [ "$resql_response" != [] ]; then
    training_data_checksum=$(echo "$resql_response" | grep -o '"trainingDataChecksum":"[^"]*' | grep -o '[^"]*$')
fi

if [ "$training_data_checksum" == "$checksum" ]; then
    already_trained_res=$(curl -H "x-ruuter-skip-authentication: true" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-already-trained")
    echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $already_trained_res
    exit 1
fi

processing_res=$(curl -H "x-ruuter-skip-authentication: true" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-processing")
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $processing_res

# POST request to train model in RASA
train_response=$(curl -s -X POST -D - --data-binary @temp "$TRAINING_RASA/model/train?force_training=true")
train_status=$(echo "$train_response" | grep -oP "HTTP/\d\.\d \K\d+")
trained_model_filename=$(echo "$train_response" | grep -i "^filename:" | sed 's/^filename: //i')
trained_model_filename=$(echo "$trained_model_filename" | tr -d '\r')

if [ "$train_status" != "200" ]; then
    echo "Model training failed with status code $train_status"
    error_res=$(curl -H "x-ruuter-skip-authentication: true" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-error")
    echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $error_res
    exit 1
fi

if $test; then
# PUT request to load currently trained model in RASA
load_status=$(curl -s -w "%{http_code}" -X PUT -H "Content-Type: application/json" -d '{"model_file":"/app/models/'$trained_model_filename'"}' "$TRAINING_RASA/model")
if [ "$load_status" != "204" ]; then
    echo "Model loading failed with status code $load_status"
    error_res=$(curl -H "x-ruuter-skip-authentication: true" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-error")
    echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $error_res
    exit 1
fi

testing_res=$(curl -H "x-ruuter-skip-authentication: true" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-testing")
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $testing_res

# POST request to merge testing yaml files
test_yaml=$(curl -X POST -H "Content-Type: application/json" -d '{"file_path":"'$TESTING_FILES_PATH'"}' "$TRAINING_DMAPPER/mergeYaml")

# POST request to test model in RASA
test_response=$(curl -s -w "%{http_code}" -X POST -d "$test_yaml" "$TRAINING_RASA/model/test/stories")
test_status="${test_response: -3}"
if [ "$test_status" != "200" ]; then
    echo "Model testing failed with status code $test_status"
    error_res=$(curl -H "x-ruuter-skip-authentication: true" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-error")
    echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $error_res
    exit 1
fi
test_body="${test_response:: -3}"

cv_res=$(curl -H "x-ruuter-skip-authentication: true" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-cross-validating")
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $cv_res

# POST request to merge cross validating yaml files
curl -X POST -H "Content-Type: application/json" -d '{"file_path":"'$CROSS_VALIDATION_FILES_PATH'"}' "$TRAINING_DMAPPER/mergeYaml" > temp2

# POST request to cross validate model in RASA
cross_validate_response=$(curl -s -w "%{http_code}" -X POST -H "Content-Type: application/x-yaml" --data-binary @temp2 "$TRAINING_RASA/model/test/intents?cross_validation_folds=2")
cross_validate_status="${cross_validate_response: -3}"

if [ "$cross_validate_status" != "200" ]; then
    echo "Model cross validating failed with status code $cross_validate_status"
    error_res=$(curl -H "x-ruuter-skip-authentication: true" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-error")
    echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $error_res
    exit 1
fi
cross_validate_body="${cross_validate_response:: -3}"
fi

copy_file_body_dto='{"destinationFilePath":"'$trained_model_filename'","destinationStorageType":"S3","sourceFilePath":"'$trained_model_filename'","sourceStorageType":"FS"}'
copy_file_response=$(curl -s -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$copy_file_body_dto" "$S3_FERRY_TRAIN/v1/files/copy")
copy_file_status="${copy_file_response: -3}"
if [ "$copy_file_status" != "201" ]; then
    echo "Copying file from local to remote storage failed with status code $copy_file_status"
    error_res=$(curl -H "x-ruuter-skip-authentication: true" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-error")
    echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $error_res
    exit 1
fi

if $test; then
add_new_model_body_dto='{"fileName":"'$trained_model_filename'","testReport":'$test_body',"crossValidationReport":'$cross_validate_body',"trainingDataChecksum":"'$checksum'"}'
echo "did do the test"
echo $add_new_model_body_dto
else
add_new_model_body_dto='{"fileName":"'$trained_model_filename'","testReport":{},"crossValidationReport":{},"trainingDataChecksum":"'$checksum'"}'
echo "did not do test"
echo $add_new_model_body_dto
fi
ready_res=$(curl -X POST -H "x-ruuter-skip-authentication: true" -H "Content-Type: application/json" -d "$add_new_model_body_dto" "$TRAINING_PUBLIC_RUUTER/rasa/model/add-new-model-ready")
echo $ready_res
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $ready_res

rm /data/$trained_model_filename
rm temp
rm temp2
echo $(date -u +"%Y-%m-%d %H:%M:%S.%3NZ") - $script_name finished
