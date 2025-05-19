*** Settings ***
Resource            /opt/robot-tests/tests/resources/common.resource
Library             /opt/robot-tests/tests/libraries/bodyRequests.py
Library             XML
Library             String

Suite Teardown      Reset Testing Environment
Test Setup          Reset Testing Environment
Test Teardown       Reset Testing Environment


*** Variables ***
# Test variables
${SUT_IP}                       10.95.82.211
${PUBLIC_ENDPOINT}              8.8.8.8

# output folder
${OUTPUT_DIR}                   /opt/robot-tests/results

# Prepare scripts
${PREPARE_APPLIANCE_SCRIPT}     /opt/robot-tests/tests/scripts/prepare_appliance.sh
${PREPARE_APPLIANCE_FILE}       /opt/robot-tests/results/prepare_appliance.json
# Basic details scripts
${GATHER_SUT_INFO_SCRIPT}       /opt/robot-tests/tests/scripts/gather_sut_info.sh
${GATHER_SUT_INFO_FILE}         /opt/robot-tests/results/sut_info.json
# Basic Tests scripts
${BASIC_TEST_SCRIPT}            /opt/robot-tests/tests/scripts/basic_test.sh
${BASIC_TEST_FILE}              /opt/robot-tests/results/basic_test.json
# Performance Tests scripts
${PERFORMANCE_TEST_SCRIPT}      /opt/robot-tests/tests/scripts/performance_test.sh
${PERFORMANCE_TEST_FILE}        /opt/robot-tests/results/performance_test.json


*** Test Cases ***
# Example 1
#    [Documentation]    Example test case 1
#    [Tags]    example-1

#    Log    Message1: ${TEST_MESSAGE}
#    Log    Message2: ${TEST_MESSAGE2}

#    Generate Cover    Tests over ONE Appliance    5/5/25

# SSH to one machine
#    [Tags]    example-2
#    ${mgmt_machine_ip}=    Set Variable    10.11.28.52
#    ${destination_ip}=    Set Variable    8.8.8.8
#    Remote Ping Connected To Mgmt
#    ...    ${mgmt_machine_ip}
#    ...    ${destination_ip}

Prepare Appliance for testing
    [Tags]    basic-1

    Execute Remote Script
    ...    ${SUT_IP}
    ...    ${PREPARE_APPLIANCE_SCRIPT}
    ...    ${PREPARE_APPLIANCE_FILE}

Retrieve basic details from SUT
    [Tags]    basic-2

    ${mgmt_machine_ip}=    Set Variable    10.11.28.52
    ${ROBOT_IPERF_SERVER}=    Get Ip For Interface    eth0

    Execute Remote Script
    ...    ${SUT_IP}
    ...    ${GATHER_SUT_INFO_SCRIPT}
    ...    ${GATHER_SUT_INFO_FILE}
    ...    args=${ROBOT_IPERF_SERVER} ${PUBLIC_ENDPOINT}

Generate General Report
    [Tags]    basic-3

    Generate Cover    Tests over ONE Appliance    5/5/25
    Generate Report Page Pdf    01-base_info.md.j2    ${GATHER_SUT_INFO_FILE}    ${OUTPUT_DIR}/01-base_info.pdf
