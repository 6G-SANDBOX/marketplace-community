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
${SUT_IP}                       ${EMPTY}
${PUBLIC_ENDPOINT}              8.8.8.8

# output folder
${OUTPUT_DIR}                   /opt/robot-tests/results

# Prepare scripts
${PREPARE_APPLIANCE_SCRIPT}     /opt/robot-tests/tests/scripts/prepare_appliance.sh
${PREPARE_APPLIANCE_FILE}       /opt/robot-tests/results/prepare_appliance.json
# Basic details scripts
${SUT_INFO_SCRIPT}              /opt/robot-tests/tests/scripts/sut_info.sh
${SUT_INFO_FILE}                /opt/robot-tests/results/sut_info.json
# Performance Tests scripts
${PERFORMANCE_TEST_SCRIPT}      /opt/robot-tests/tests/scripts/performance_test.sh
${PERFORMANCE_TEST_FILE}        /opt/robot-tests/results/performance_test.json


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

    ${ROBOT_IPERF_SERVER}=    Get Ip For Interface    eth0

    Execute Remote Script
    ...    ${SUT_IP}
    ...    ${SUT_INFO_SCRIPT}
    ...    ${SUT_INFO_FILE}
    ...    args=--iperf-ip ${ROBOT_IPERF_SERVER} --public-endpoint ${PUBLIC_ENDPOINT}

Performance Tests
    [Documentation]    Run performance tests
    [Tags]    step-3

    ${ROBOT_IPERF_SERVER}=    Get Ip For Interface    eth0

    Execute Remote Script
    ...    ${SUT_IP}
    ...    ${PERFORMANCE_TEST_SCRIPT}
    ...    ${PERFORMANCE_TEST_FILE}
    ...    args=--iperf-ip ${ROBOT_IPERF_SERVER}

Generate Report
    [Documentation]    Generate General Report
    [Tags]    step-4

    # Generate Cover
    ${current_date}=    Get Current Date    result_format=%d/%m/%Y %H:%M:%S
    Generate Cover    Tests over ONE Appliance    ${current_date}    ${OUTPUT_DIR}/000-cover.pdf
    Create Watermark    ${OUTPUT_DIR}/watermark.pdf

    # Generate Functional report pages
    Generate Report Page Pdf
    ...    000-prepare_info.md.j2
    ...    ${PREPARE_APPLIANCE_FILE}
    ...    ${OUTPUT_DIR}/000-prepare_info.pdf

    # Generate Functional report pages
    Generate Report Page Pdf
    ...    010-functional_info.md.j2
    ...    ${SUT_INFO_FILE}
    ...    ${OUTPUT_DIR}/010-functional_info.pdf

    # Generate perfomance report pages
    Generate Report Page Pdf
    ...    020-performance_info.md.j2
    ...    ${PERFORMANCE_TEST_FILE}
    ...    ${OUTPUT_DIR}/020-performance_info.pdf

    # Create a list of PDFs to join
    ${PDFS_TO_JOIN}=    Create List
    ...    ${OUTPUT_DIR}/000-prepare_info.pdf
    ...    ${OUTPUT_DIR}/010-functional_info.pdf
    ...    ${OUTPUT_DIR}/020-performance_info.pdf

    Apply Watermark    ${PDFS_TO_JOIN}    ${OUTPUT_DIR}/watermark.pdf

    # Join all PDFs
    ${PDFS_TO_JOIN}=    Create List
    ...    ${OUTPUT_DIR}/000-cover.pdf
    ...    @{PDFS_TO_JOIN}

    Join Pdfs    ${PDFS_TO_JOIN}    ${OUTPUT_DIR}/final_report.pdf
