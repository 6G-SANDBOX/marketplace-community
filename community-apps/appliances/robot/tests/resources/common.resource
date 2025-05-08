*** Settings ***
Library         /opt/robot-tests/tests/libraries/helpers.py
Library    Process
Library    Collections
Resource        /opt/robot-tests/tests/resources/common/basicRequests.robot
Library    /opt/robot-tests/tests/libraries/report/report.py
Library   SSHLibrary

*** Variables ***


*** Keywords ***
Reset Testing Environment
    Log   Reset testing environment

Check Response Variable Type And Values
    [Arguments]    ${resp}    ${status_code}    ${variable_type}    &{input_parameters}
    Status Should Be    ${status_code}    ${resp}
    Check Variable    ${resp.json()}    ${variable_type}
    FOR    ${input}    IN    @{input_parameters}
        Log    ${input}=${input_parameters['${input}']}
        IF     "${input}"=="invalidParams"
            Should Be Equal    ${resp.json()['${input}']}    ${input_parameters['${input}']}
        ELSE
            Should Match Regexp    "${resp.json()['${input}']}"    "${input_parameters['${input}']}"
        END
    END

Remove Keys From Object
    [Arguments]    ${input}    @{keys_to_remove}

    ${filtered_input}=    Remove Keys From Object Helper    ${input}    ${keys_to_remove}

    RETURN    ${filtered_input}

Test ${TEST NAME} Currently Not Supported
    Log    Test "${TEST NAME}" Currently not supported    WARN
    Skip    Test "${TEST NAME}" Currently not supported



