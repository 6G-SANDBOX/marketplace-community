FROM ubuntu:22.04

LABEL maintainer="Jorge Moratinos Salcines <jorge.moratinossalcines@telefonica.com>"
LABEL version="3.0"
LABEL description="Docker to run Robot Framework"

# Evitar prompts interactivos
ENV DEBIAN_FRONTEND=noninteractive \
    ROBOT_DIRECTORY=/opt/robot-tests \
    ROBOT_COMMON_DIRECTORY=/opt/robot-tests/common \
    ROBOT_TESTS_DIRECTORY=/opt/robot-tests/tests \
    ROBOT_RESULTS_DIRECTORY=/opt/robot-tests/results

# Crear estructura de directorios y volúmenes
RUN mkdir -p \
    $ROBOT_DIRECTORY \
    $ROBOT_COMMON_DIRECTORY \
    $ROBOT_TESTS_DIRECTORY \
    $ROBOT_RESULTS_DIRECTORY
VOLUME $ROBOT_COMMON_DIRECTORY $ROBOT_TESTS_DIRECTORY $ROBOT_RESULTS_DIRECTORY

WORKDIR $ROBOT_DIRECTORY

# Habilitar 'universe' y paquetes base (incluye Python + venv + pip)
RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    add-apt-repository -y universe && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        gnupg \
        gpg-agent \
        dirmngr \
        build-essential \
        bash \
        bash-completion \
        less \
        dpkg \
        libxml2 \
        libxslt1-dev \
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
        wkhtmltopdf \
        fonts-dejavu \
        python3 \
        python3-venv \
        python3-pip \
        python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Yarn (vía npm). El symlink asegura /usr/bin/yarn
RUN npm install -g yarn && ln -sf /usr/local/bin/yarn /usr/bin/yarn

# Crear y activar el venv. Añadimos el venv al PATH para el resto de RUNs.
RUN python3 -m venv /opt/venv && \
    /opt/venv/bin/python -m pip install --upgrade pip setuptools wheel
ENV PATH="/opt/venv/bin:$PATH"

# Copiar requirements y scripts
COPY basicRequirements.txt /root/
COPY basicRobotInstall.sh /root/
COPY entrypoint.sh linter_entrypoint.sh featdoc_entrypoint.sh libdoc_entrypoint.sh /root/

# Instalar dependencias Python (dentro del venv)
RUN chmod +x /root/basicRobotInstall.sh && \
    /root/basicRobotInstall.sh /root/basicRequirements.txt && \
    sed -i 's|/bin/ash|/bin/bash|g' /etc/passwd

# Sustituir placeholders en los entrypoints
RUN for script in entrypoint.sh linter_entrypoint.sh featdoc_entrypoint.sh libdoc_entrypoint.sh; do \
        sed -i "s|ROBOT_DIRECTORY|$ROBOT_DIRECTORY|g" /root/$script && \
        sed -i "s|ROBOT_TESTS_DIRECTORY|$ROBOT_TESTS_DIRECTORY|g" /root/$script && \
        sed -i "s|ROBOT_COMMON_DIRECTORY|$ROBOT_COMMON_DIRECTORY|g" /root/$script && \
        sed -i "s|ROBOT_RESULTS_DIRECTORY|$ROBOT_RESULTS_DIRECTORY|g" /root/$script && \
        chmod +x /root/$script; \
    done

ENTRYPOINT [ "/root/entrypoint.sh" ]
