FROM ubuntu:22.04
LABEL maintainer="Jorge Moratinos Salcines <jorge.moratinossalcines@telefonica.com>"
LABEL version="2.0"
LABEL description="Docker to run Robot Framework"

ENV ROBOT_DIRECTORY=/opt/robot-tests
ENV ROBOT_COMMON_DIRECTORY=$ROBOT_DIRECTORY/common
ENV ROBOT_TESTS_DIRECTORY=$ROBOT_DIRECTORY/tests
ENV ROBOT_RESULTS_DIRECTORY=$ROBOT_DIRECTORY/results

# Create directories structure
RUN mkdir $ROBOT_DIRECTORY
RUN mkdir $ROBOT_COMMON_DIRECTORY
RUN mkdir $ROBOT_TESTS_DIRECTORY
RUN mkdir $ROBOT_RESULTS_DIRECTORY


# Create Volumes for docker
# VOLUME $ROBOT_DIRECTORY
VOLUME $ROBOT_COMMON_DIRECTORY
VOLUME $ROBOT_TESTS_DIRECTORY
VOLUME $ROBOT_RESULTS_DIRECTORY

WORKDIR $ROBOT_DIRECTORY

ENV DEBIAN_FRONTEND=noninteractive
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Install dependencies
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing software-properties-common
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing build-essential
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing bash 
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing bash-completion
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing libxml2
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing libxslt-dev
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing curl
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing yarn
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing less
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing dpkg
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing wget
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing python3
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing python3-dev
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing libxslt-dev
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing libffi-dev
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing python3-pip
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing python3-venv
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing python2.7-dev
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing libssl-dev
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing libldap2-dev

RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing libsasl2-dev
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing ldap-utils
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing slapd
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing tox
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing lcov
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing valgrind
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing tshark
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing nodejs
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing npm
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing gnupg2
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing gpg-agent
RUN apt-get update && apt-get install -y --no-install-recommends --fix-missing wkhtmltopdf

RUN add-apt-repository -y ppa:deadsnakes/ppa
RUN apt-get update
RUN apt-get install -y --fix-missing python3.10 python3.10-venv python3.10-dev

RUN mkdir /opt/venv
RUN python3.10 -m venv /opt/venv

ADD basicRequirements.txt /root/

ADD basicRobotInstall.sh /root/
RUN chmod a+x /root/basicRobotInstall.sh \
    && /root/basicRobotInstall.sh /root/basicRequirements.txt
RUN sed -i 's/\/bin\/ash/\/bin\/bash/g' /etc/passwd

ADD entrypoint.sh /root/
ADD linter_entrypoint.sh /root/
ADD featdoc_entrypoint.sh /root/
ADD libdoc_entrypoint.sh /root/


RUN sed  -i 's|ROBOT_DIRECTORY|'$ROBOT_DIRECTORY'|g' /root/entrypoint.sh
RUN sed  -i 's|ROBOT_TESTS_DIRECTORY|'$ROBOT_TESTS_DIRECTORY'|g' /root/entrypoint.sh
RUN sed  -i 's|ROBOT_COMMON_DIRECTORY|'$ROBOT_COMMON_DIRECTORY'|g' /root/entrypoint.sh
RUN sed  -i 's|ROBOT_RESULTS_DIRECTORY|'$ROBOT_RESULTS_DIRECTORY'|g' /root/entrypoint.sh

RUN sed  -i 's|ROBOT_DIRECTORY|'$ROBOT_DIRECTORY'|g' /root/linter_entrypoint.sh
RUN sed  -i 's|ROBOT_TESTS_DIRECTORY|'$ROBOT_TESTS_DIRECTORY'|g' /root/linter_entrypoint.sh
RUN sed  -i 's|ROBOT_COMMON_DIRECTORY|'$ROBOT_COMMON_DIRECTORY'|g' /root/linter_entrypoint.sh


RUN sed  -i 's|ROBOT_DIRECTORY|'$ROBOT_DIRECTORY'|g' /root/featdoc_entrypoint.sh
RUN sed  -i 's|ROBOT_TESTS_DIRECTORY|'$ROBOT_TESTS_DIRECTORY'|g' /root/featdoc_entrypoint.sh
RUN sed  -i 's|ROBOT_COMMON_DIRECTORY|'$ROBOT_COMMON_DIRECTORY'|g' /root/featdoc_entrypoint.sh

RUN sed  -i 's|ROBOT_DIRECTORY|'$ROBOT_DIRECTORY'|g' /root/libdoc_entrypoint.sh
RUN sed  -i 's|ROBOT_TESTS_DIRECTORY|'$ROBOT_TESTS_DIRECTORY'|g' /root/libdoc_entrypoint.sh
RUN sed  -i 's|ROBOT_COMMON_DIRECTORY|'$ROBOT_COMMON_DIRECTORY'|g' /root/libdoc_entrypoint.sh


RUN chmod a+x /root/entrypoint.sh
RUN chmod a+x /root/linter_entrypoint.sh
RUN chmod a+x /root/featdoc_entrypoint.sh
RUN chmod a+x /root/libdoc_entrypoint.sh

ENTRYPOINT [ "/root/entrypoint.sh" ]
