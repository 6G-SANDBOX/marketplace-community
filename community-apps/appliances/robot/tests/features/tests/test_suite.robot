*** Settings ***
Resource            /opt/robot-tests/tests/resources/common.resource
Library             /opt/robot-tests/tests/libraries/bodyRequests.py
Library             XML
Library             String
Library             DateTime

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
# PDF Report
${PDF_COVER_FILE}               /opt/robot-tests/results/cover.pdf


*** Test Cases ***
Prepare Appliance for testing
    [Documentation]    Prepare the appliance for testing
    [Tags]    step-1

    Execute Remote Script
    ...    ${SUT_IP}
    ...    ${PREPARE_APPLIANCE_SCRIPT}
    ...    ${PREPARE_APPLIANCE_FILE}

Retrieve basic details from SUT
    [Documentation]    Retrieve basic details from SUT
    [Tags]    step-2

    ${mgmt_machine_ip}=    Set Variable    10.11.28.52
    ${ROBOT_IPERF_SERVER}=    Get Ip For Interface    eth0

    Execute Remote Script
    ...    ${SUT_IP}
    ...    ${GATHER_SUT_INFO_SCRIPT}
    ...    ${GATHER_SUT_INFO_FILE}
    ...    args=${ROBOT_IPERF_SERVER} ${PUBLIC_ENDPOINT}

Generate Report
    [Documentation]    Generate General Report
    [Tags]    step-3

    ${current_date}=    Get Current Date    result_format=%d/%m/%Y %H:%M:%S
    Generate Cover    Tests over ONE Appliance    ${current_date}
    Generate Report Page Pdf    01-base_info.md.j2    ${GATHER_SUT_INFO_FILE}    ${OUTPUT_DIR}/01-base_info.pdf

    ${PDFS_TO_JOIN}=    Create List    ${PDF_COVER_FILE}    ${OUTPUT_DIR}/01-base_info.pdf
    Join Pdfs    ${PDFS_TO_JOIN}    ${OUTPUT_DIR}/report.pdf
