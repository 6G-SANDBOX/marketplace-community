#!/bin/bash
source /opt/venv/bin/activate;
BASE_DIRECTORY=ROBOT_DIRECTORY
BASE_REQ_FILE=$BASE_DIRECTORY/requirements.txt
COMMON_REQ_FILE=ROBOT_COMMON_DIRECTORY/requirements.txt
TESTS_REQ_FILE=ROBOT_TESTS_DIRECTORY/requirements.txt

ARGUMENTS=()
OPTIONS=()

timestamp=$(date +"%Y%m%d_%H%M%S")

while [ -n "$1" ]; do # while loop starts

        case "$1" in
        --*)
            OPTIONS+=("$1" "$2")
            shift
            ;;

        *) 
            ARGUMENTS+=("ROBOT_TESTS_DIRECTORY/$1")
            ;;
        esac
        shift
done

echo "Arguments: ${ARGUMENTS[@]}"
echo "Options: ${OPTIONS[@]}"

if [[ -f "$BASE_REQ_FILE" ]]; then
    rm $BASE_REQ_FILE
fi

echo '# Requirements file for tests.' > $BASE_REQ_FILE

if [[ -f "$COMMON_REQ_FILE" ]]; then
    cat $COMMON_REQ_FILE >> $BASE_REQ_FILE
fi

if [[ -f "$TESTS_REQ_FILE" ]]; then
    cat $TESTS_REQ_FILE >> $BASE_REQ_FILE
fi

cat $BASE_REQ_FILE | sort | uniq > $BASE_REQ_FILE.tmp ; mv $BASE_REQ_FILE.tmp $BASE_REQ_FILE

if [ ${#ARGUMENTS[@]} -eq 0 ]; then
    ARGUMENTS=("ROBOT_TESTS_DIRECTORY/")
fi

pip install -r $BASE_REQ_FILE
robot -d ROBOT_RESULTS_DIRECTORY/$timestamp --xunit xunit.xml "${OPTIONS[@]}" "${ARGUMENTS[@]}"
