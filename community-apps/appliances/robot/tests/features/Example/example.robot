*** Settings ***
Resource            /opt/robot-tests/tests/resources/common.resource
Library             /opt/robot-tests/tests/libraries/bodyRequests.py
Library             XML
Library             String

Suite Teardown      Reset Testing Environment
Test Setup          Reset Testing Environment
Test Teardown       Reset Testing Environment


*** Variables ***


*** Test Cases ***
Example 1
    [Tags]    example-1

    [Documentation]    Example test case 1

    Log    Message1: ${TEST_MESSAGE}
    Log    Message2: ${TEST_MESSAGE2}

    Generate Cover    Tests over ONE Appliance     5/5/25    