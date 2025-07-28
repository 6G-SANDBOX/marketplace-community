FROM ubuntu:22.04
LABEL maintainer="Jorge Moratinos Salcines <jorge.moratinossalcines@telefonica.com>"
LABEL version="2.0"
LABEL description="Docker to run Robot Framework"

ENV ROBOT_DIRECTORY=/opt/robot-tests
ENV ROBOT_COMMON_DIRECTORY=$ROBOT_DIRECTORY/common
ENV ROBOT_TESTS_DIRECTORY=$ROBOT_DIRECTORY/tests
ENV ROBOT_RESULTS_DIRECTORY=$ROBOT_DIRECTORY/results

# Create directories structure
RUN mkdir -p $ROBOT_COMMON_DIRECTORY $ROBOT_TESTS_DIRECTORY $ROBOT_RESULTS_DIRECTORY

# Create Volumes for docker
# VOLUME $ROBOT_DIRECTORY
VOLUME $ROBOT_COMMON_DIRECTORY
VOLUME $ROBOT_TESTS_DIRECTORY
VOLUME $ROBOT_RESULTS_DIRECTORY

WORKDIR $ROBOT_DIRECTORY

ENV DEBIAN_FRONTEND=noninteractive
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

# Install dependencies
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends --fix-missing \
        software-properties-common \
        build-essential \
        bash \
        bash-completion \
        libxml2 \
        libxslt-dev \
        curl \
        yarn \
        less \
        dpkg \
        wget \
        python3 \
        python3-dev \
        libffi-dev \
        python3-pip \
        python3-venv \
        python2.7-dev \
        libssl-dev \
        libldap2-dev \
        libsasl2-dev \
        ldap-utils \
        slapd \
        tox \
        lcov \
        valgrind \
        tshark \
        nodejs \
        npm \
        gnupg2 \
        gpg-agent \
        wkhtmltopdf && \
    add-apt-repository -y ppa:deadsnakes/ppa && \
    apt-get update && \
    apt-get install -y --fix-missing python3.10 python3.10-venv python3.10-dev && \
    mkdir /opt/venv && \
    python3.10 -m venv /opt/venv && \
    apt-get clean && rm -rf /var/lib/apt/lists/*


ADD basicRequirements.txt /root/
ADD basicRobotInstall.sh /root/
ADD entrypoint.sh /root/
ADD linter_entrypoint.sh /root/
ADD featdoc_entrypoint.sh /root/
ADD libdoc_entrypoint.sh /root/


RUN chmod a+x /root/basicRobotInstall.sh /root/entrypoint.sh /root/linter_entrypoint.sh /root/featdoc_entrypoint.sh /root/libdoc_entrypoint.sh && \
    /root/basicRobotInstall.sh /root/basicRequirements.txt && \
    sed -i 's|/bin/ash|/bin/bash|g' /etc/passwd && \
    sed  -i 's|ROBOT_DIRECTORY|'$ROBOT_DIRECTORY'|g' /root/entrypoint.sh /root/linter_entrypoint.sh /root/featdoc_entrypoint.sh /root/libdoc_entrypoint.sh && \
    sed  -i 's|ROBOT_TESTS_DIRECTORY|'$ROBOT_TESTS_DIRECTORY'|g' /root/entrypoint.sh /root/linter_entrypoint.sh /root/featdoc_entrypoint.sh /root/libdoc_entrypoint.sh && \
    sed  -i 's|ROBOT_COMMON_DIRECTORY|'$ROBOT_COMMON_DIRECTORY'|g' /root/entrypoint.sh /root/linter_entrypoint.sh /root/featdoc_entrypoint.sh /root/libdoc_entrypoint.sh && \
    sed  -i 's|ROBOT_RESULTS_DIRECTORY|'$ROBOT_RESULTS_DIRECTORY'|g' /root/entrypoint.sh

ENTRYPOINT [ "/root/entrypoint.sh" ]
