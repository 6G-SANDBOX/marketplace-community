*** Settings ***
Resource            /opt/robot-tests/tests/resources/common.resource
Library             /opt/robot-tests/tests/libraries/bodyRequests.py
Library             XML
Library             String

Suite Teardown      Reset Testing Environment
Test Setup          Reset Testing Environment
Test Teardown       Reset Testing Environment


*** Variables ***
${GATHER_SUT_INFO_SCRIPT}       /opt/robot-tests/tests/scripts/gather_sut_info.sh
${SUT_INFO_FILE}                /opt/robot-tests/results/sut_info.json
${PUBLIC_ENDPOINT}              8.8.8.8


*** Test Cases ***
Example 1
    [Documentation]    Example test case 1
    [Tags]    example-1

    Log    Message1: ${TEST_MESSAGE}
    Log    Message2: ${TEST_MESSAGE2}

    Generate Cover    Tests over ONE Appliance    5/5/25

SSH to one machine
    [Tags]    example-2
    ${mgmt_machine_ip}=    Set Variable    10.11.28.52
    ${destination_ip}=    Set Variable    8.8.8.8
    Remote Ping Connected To Mgmt
    ...    ${mgmt_machine_ip}
    ...    ${destination_ip}
    ...

Retrieve basic details from SUT
    [Tags]    basic-1

    ${mgmt_machine_ip}=    Set Variable    10.11.28.52
    ${ROBOT_IPERF_SERVER}=    Get Ip For Interface    eth0

    # ${DIR}    ${FILE}    Split Path    ${FULL_PATH}

    Execute Remote Script
    ...    ${mgmt_machine_ip}
    ...    ${GATHER_SUT_INFO_SCRIPT}
    ...    ${SUT_INFO_FILE}
    ...    args=${ROBOT_IPERF_SERVER} ${PUBLIC_ENDPOINT}

    # Put File    ${GATHER_SUT_INFO_SCRIPT}    /tmp/gather_sut_info.sh    mode=755    scp=ON
    # Execute Remote Commands At Ip    ${mgmt_machine_ip}    True    /tmp/gather_sut_info.sh    /tmp/sut_info.json    ${ROBOT_IPERF_SERVER}    ${PUBLIC_ENDPOINT}
    # Get File    ${}

    # Get Hostname
    # Get Interfaces
    # Get OS Details
    # Get GPU Details
    # Get Interface to be used by iperf
    # Check Connectivity
    # Check Mounted Disks
