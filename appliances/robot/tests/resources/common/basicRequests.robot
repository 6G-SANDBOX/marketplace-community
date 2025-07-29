*** Settings ***
Documentation       This resource file contains the basic requests used by Capif. NGINX_HOSTNAME and CAPIF_AUTH can be set as global variables, depends on environment used

Library             RequestsLibrary
Library             Collections
Library             OperatingSystem
Library             XML
Library             String
Library             SSHLibrary


*** Variables ***
${HOST}             localhost
${USERNAME}         root
${PASSWORD}         test
${PRIVATE_KEY_FILE}       /opt/robot-tests/tests/certs/id_rsa
${GPU_PLOT_FILENAME}            gpu_usage_plot.png
${REMOTE_TMP_FOLDER}   /tmp/script_robot_tests


*** Keywords ***
Remote Ping
    [Documentation]    Execute ping in remote machine to host indicated
    [Arguments]    ${host}    ${options}=

    ${ping_command}=    Ping Command    ${destination_ip}
    ${rc}=    Execute Command    ${ping_command} -c 1 ${options} ${host}    return_stdout=False    return_rc=True
    Should Be Equal As Integers    ${rc}    0    # succeeded

Remote Ping Connected To Mgmt
    [Documentation]    Execute ping in remote machine to host indicated
    [Arguments]    ${mgmt_machine_ip}    ${destination_ip}    ${options}=    ${user}=${NONE}    ${password}=${NONE}

    ${ping_command}=    Ping Command    ${destination_ip}

    ${use_user_pass_auth}=    Evaluate    '${user}' != 'None' and '${password}' != 'None'

    IF    ${use_user_pass_auth}
        Open Connection With User And Password    ${mgmt_machine_ip}    ${user}    ${password}
    ELSE
        Open Connection With Public Key And Log In    ${mgmt_machine_ip}    ${USERNAME}    ${PRIVATE_KEY_FILE}
    END

    ${stdout}    ${rc}=    Execute Command
    ...    ${ping_command} -c 1 ${options} ${destination_ip}
    ...    return_stdout=True
    ...    return_rc=True
    Close Connection
    Log    ${stdout}
    Should Be Equal As Integers    ${rc}    0    # succeeded

Execute Remote Script
    [Arguments]
    ...    ${ip}
    ...    ${local_script_path}
    ...    ${local_output_file}=${NONE}
    ...    ${args}=
    ...    ${user}=${NONE}
    ...    ${password}=${NONE}

    ${use_user_pass_auth}=    Evaluate    '${user}' != 'None' and '${password}' != 'None'

    IF    ${use_user_pass_auth}
        Open Connection With User And Password    ${ip}    ${user}    ${password}
    ELSE
        Open Connection With Public Key And Log In    ${ip}    ${USERNAME}    ${PRIVATE_KEY_FILE}
    END

    Execute Command    mkdir -p ${REMOTE_TMP_FOLDER}

    ${local_directory}    ${script_filename}=    Split Path    ${local_script_path}

    Put File    ${local_script_path}    ${REMOTE_TMP_FOLDER}/${script_filename}    mode=755    scp=ON

    ${rc}=    Set Variable
    ${stdout}=    Set Variable

    IF    "${local_output_file}" != "${NONE}"
        ${local_output_directory}    ${output_filename}=    Split Path    ${local_output_file}
        ${stdout}    ${rc}=    Execute Command
        ...    ${REMOTE_TMP_FOLDER}/${script_filename} --json ${REMOTE_TMP_FOLDER}/${output_filename} ${args}
        ...    return_stdout=True
        ...    return_rc=True
        Log    ${stdout}
        Run Keyword And Ignore Error  SSHLibrary.Get File    ${REMOTE_TMP_FOLDER}/*   ${local_output_directory}/
        # Run Keyword And Ignore Error  SSHLibrary.Get File    /tmp/${GPU_PLOT_FILENAME}    /opt/robot-tests/results/${GPU_PLOT_FILENAME}
        Log    ${local_output_file}
        # Execute Command    sudo rm -f ${REMOTE_TMP_FOLDER}//${output_filename}
    ELSE
        ${stdout}    ${rc}=    Execute Command
        ...    /tmp/${script_filename} ${args}
        ...    return_stdout=True
        ...    return_rc=True
        Log    ${stdout}
    END
    Execute Command    sudo ls -l ${REMOTE_TMP_FOLDER}/
    Execute Command    sudo rm -rf ${REMOTE_TMP_FOLDER}/
    Close Connection

    Should Be Equal As Integers    ${rc}    0    # succeeded

Execute Remote Commands At Ip Using User Password
    [Documentation]    Execute ping in remote machine to host indicated
    [Arguments]    ${ip}    ${user}    ${password}    ${sudo_active}    @{commands}

    Open Connection With User And Password    ${ip}    ${user}    ${password}
    ${stdout}=    Run Keyword And Continue On Failure    Execute Remote Commands    ${sudo_active}    @{commands}
    Close Connection
    RETURN    ${stdout}

Execute Remote Commands At Ip
    [Documentation]    Execute ping in remote machine to host indicated
    [Arguments]    ${ip}    ${sudo_active}    @{commands}

    Open Connection With Public Key And Log In    ${ip}    ${USERNAME}    ${PRIVATE_KEY_FILE}
    ${stdout}=    Run Keyword And Continue On Failure    Execute Remote Commands    ${sudo_active}    @{commands}
    Close Connection
    RETURN    ${stdout}

Execute Remote Commands
    [Documentation]    Execute ping in remote machine to host indicated
    [Arguments]    ${sudo_active}    @{commands}

    ${sudo}=    Set Variable If
    ...    ${sudo_active} == True    sudo
    ...    ${sudo_active} != True    ${EMPTY}
    FOR    ${command}    IN    @{commands}
        ${stdout}    ${stderr}    ${rc}=    Execute Command
        ...    ${sudo} ${command}
        ...    return_stdout=True
        ...    return_stderr=True
        ...    return_rc=True

        Log Many    ${stdout}
        Log Many    ${stderr}
        Should Be Equal As Integers    ${rc}    0    # succeeded
    END
    RETURN    ${stdout}

# Connection keywords

Open Connection With Public Key And Log In
    [Documentation]    Connect to host using public key to login. This login operation is needed before execute any remote command
    [Arguments]    ${host}    ${username}    ${private_key_file}

    Log    Connecting to host ${host} with user ${username} using public key stored in ${private_key_file}
    ${index}=    Open Connection    ${host}
    ${output}=    Login With Public Key    ${username}    ${private_key_file}
    Read Until Regexp    \[?${username}@.*:?~\]?\$
    Should Match Regexp    ${output}    \[?${username}@.*:?~\]?\$

    RETURN    ${index}

Open Connection With User And Password
    [Documentation]    Connect to host using user and password and optional set port
    [Arguments]    ${host}    ${username}    ${password}    ${port}=22

    Log    Connecting to host ${host} with user ${username} using password to port ${port}
    ${index}=    Open Connection    ${host}    port=${port}
    ${output}=    Login    ${username}    ${password}
    Read Until Regexp    \[?${username}@.*:?~\]?\$
    Check Shell Output    ${output}    ${username}

    RETURN    ${index}

Close All Ssh Connections
    ${result}=    Close All Connections

    RETURN    ${result}

Close Ssh Connection
    [Documentation]    This Keyword close indicated connection
    ...    and leave current connection selected
    [Arguments]    ${index}

    ${current_connection}=    Get Connection
    Switch Connection    ${index}
    Close Connection
    IF    '${index}' != '${current_connection.index}'
        ${result}=    Switch Connection    ${current_connection.index}
    ELSE
        ${result}=    Set Variable    ${None}
    END

    RETURN    ${result}

# Connection Helper

Check Shell Output
    [Arguments]    ${output}    ${username}

    ${REGEXP_CMD_SHELL}=    Set Variable    \[?${username}@.*:?~\]?\$
    Should Match Regexp    ${output}    ${REGEXP_CMD_SHELL}

# Checks in remote machines

Check If Port is listening
    [Arguments]    ${port}

    Check If Process Is Listening At Port    process_name=    port=${port}

Check If Process Is Listening At Port
    [Arguments]    ${process_name}    ${port}

    ${stdout}    ${stderr}=    Execute Command
    ...    sudo netstat -putan | grep "${process_name}" | grep "LISTEN"
    ...    return_stderr=True
    ...    timeout=5 seconds
    Should Be Empty    ${stderr}
    Should Match Regexp    ${stdout}    (tcp .* 0\.0\.0\.0:${port} + 0\.0\.0\.0:\*|tcp6 .* :::${port} + :::\*)
