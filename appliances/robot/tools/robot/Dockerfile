FROM python:3.10-slim

LABEL maintainer="Jorge Moratinos Salcines <jorge.moratinossalcines@telefonica.com>"
LABEL version="2.0"
LABEL description="Docker to run Robot Framework"

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    ROBOT_DIRECTORY=/opt/robot-tests \
    ROBOT_COMMON_DIRECTORY=/opt/robot-tests/common \
    ROBOT_TESTS_DIRECTORY=/opt/robot-tests/tests \
    ROBOT_RESULTS_DIRECTORY=/opt/robot-tests/results

# Create directories
RUN mkdir -p \
    $ROBOT_DIRECTORY \
    $ROBOT_COMMON_DIRECTORY \
    $ROBOT_TESTS_DIRECTORY \
    $ROBOT_RESULTS_DIRECTORY

# Create docker volumes
VOLUME $ROBOT_COMMON_DIRECTORY $ROBOT_TESTS_DIRECTORY $ROBOT_RESULTS_DIRECTORY

# Set the working directory
WORKDIR $ROBOT_DIRECTORY

# Install dependencies
RUN apt-get update && apt-get upgrade -y && \
    apt-get install -y --no-install-recommends software-properties-common && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
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
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create a virtual environment
RUN python3.10 -m venv /opt/venv

# Copy requirements files and scripts
COPY basicRequirements.txt /root/
COPY basicRobotInstall.sh /root/
COPY entrypoint.sh linter_entrypoint.sh featdoc_entrypoint.sh libdoc_entrypoint.sh /root/

# Install Python packages
RUN chmod +x /root/basicRobotInstall.sh && \
    /root/basicRobotInstall.sh /root/basicRequirements.txt && \
    sed -i 's|/bin/ash|/bin/bash|g' /etc/passwd

# Replace placeholders in entrypoint scripts
RUN for script in entrypoint.sh linter_entrypoint.sh featdoc_entrypoint.sh libdoc_entrypoint.sh; do \
        sed -i "s|ROBOT_DIRECTORY|$ROBOT_DIRECTORY|g" /root/$script && \
        sed -i "s|ROBOT_TESTS_DIRECTORY|$ROBOT_TESTS_DIRECTORY|g" /root/$script && \
        sed -i "s|ROBOT_COMMON_DIRECTORY|$ROBOT_COMMON_DIRECTORY|g" /root/$script && \
        sed -i "s|ROBOT_RESULTS_DIRECTORY|$ROBOT_RESULTS_DIRECTORY|g" /root/$script && \
        chmod +x /root/$script; \
    done

ENTRYPOINT [ "/root/entrypoint.sh" ]