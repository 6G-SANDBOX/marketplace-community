*** Settings ***
Resource            /opt/robot-tests/tests/resources/common.resource
Library             /opt/robot-tests/tests/libraries/bodyRequests.py
Library             XML
Library             String

Suite Teardown      Reset Testing Environment
Test Setup          Reset Testing Environment
Test Teardown       Reset Testing Environment


*** Variables ***
${OUTPUT_DIR}                   /opt/robot-tests/results
${GATHER_SUT_INFO_SCRIPT}       /opt/robot-tests/tests/scripts/gather_sut_info.sh
${SUT_INFO_FILE}                /opt/robot-tests/results/sut_info.json
${PUBLIC_ENDPOINT}              8.8.8.8
${PREPARE_APPLIANCE_SCRIPT}     /opt/robot-tests/tests/scripts/prepare_appliance.sh
${PREPARE_APPLIANCE_FILE}       /opt/robot-tests/results/prepare_appliance.json


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

    ${mgmt_machine_ip}=    Set Variable    10.11.28.52

    Execute Remote Script
    ...    ${mgmt_machine_ip}
    ...    ${PREPARE_APPLIANCE_SCRIPT}
    ...    ${PREPARE_APPLIANCE_FILE}

Retrieve basic details from SUT
    [Tags]    basic-2

    ${mgmt_machine_ip}=    Set Variable    10.11.28.52
    ${ROBOT_IPERF_SERVER}=    Get Ip For Interface    eth0

    Execute Remote Script
    ...    ${mgmt_machine_ip}
    ...    ${GATHER_SUT_INFO_SCRIPT}
    ...    ${SUT_INFO_FILE}
    ...    args=${ROBOT_IPERF_SERVER} ${PUBLIC_ENDPOINT}

Generate General Report
    [Tags]    basic-3

    ${mgmt_machine_ip}=    Set Variable
    Generate Cover    Tests over ONE Appliance    5/5/25
    Generate Report Page Pdf    01-base_info.md.j2    ${SUT_INFO_FILE}    ${OUTPUT_DIR}/01-base_info.pdf
