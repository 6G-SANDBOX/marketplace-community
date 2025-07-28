*** Settings ***
Resource        /opt/robot-tests/tests/resources/common.resource

Suite Setup     Prepare environment
# Suite Teardown  Reset Testing Environment

Force Tags      all


*** Keywords ***
Prepare environment
    Log    "Prepare environment"
