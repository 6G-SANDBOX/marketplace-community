#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Appliance metadata
# ------------------------------------------------------------------------------

ONE_SERVICE_NAME='6G-Sandbox Jenkins'
ONE_SERVICE_VERSION='0.3.0'   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='Appliance with Jenkins preinstalled and configured to serve 6G-Sandbox sites.'
ONE_SERVICE_DESCRIPTION=$(cat <<EOF
This appliance installs the latest version of Jenkins LTS from the official download and configures it to be ready to serve a 6G-SANDBOX site.

The image is based on an Ubuntu 22.04 cloud image with the OpenNebula [contextualization package](http://docs.opennebula.io/6.6/management_and_operations/references/kvm_contextualization.html).

Run with default values and manually configure the credentials from Jenkins WebUI, or use contextualization variables to automate the bootstrap.
Default Jenkins credentials (if ONEAPP_JENKINS_USERNAME and ONEAPP_JENKINS_PASSWORD are unspecified) are admin:admin

After deploying the appliance, check the status of the deployment in /etc/one-appliance/status. You chan check the appliance logs in /var/log/one-appliance/.

**WARNING: The appliance does not permit recontextualization. Modifying the context variables will not have any real efects on the running instance.**
EOF
)

ONE_SERVICE_RECONFIGURABLE=false


# ------------------------------------------------------------------------------
# List of contextualization parameters
# ------------------------------------------------------------------------------

ONE_SERVICE_PARAMS=(
    'ONEAPP_JENKINS_USERNAME'                  'configure'  'The username for the Jenkins admin user'                                        'O|text'
    'ONEAPP_JENKINS_PASSWORD'                  'configure'  'The password for the Jenkins admin user'                                        'O|text'
    'ONEAPP_JENKINS_SITES_TOKEN'               'configure'  'Token to encrypt and decrypt the 6G-Sandbox-Sites repository files for your site using Ansible Vault'  'M|password'
    'ONEAPP_JENKINS_OPENNEBULA_ENDPOINT'       'configure'  'The URL of your OpenNebula XML-RPC Endpoint API'                                'M|text'
    'ONEAPP_JENKINS_OPENNEBULA_FLOW_ENDPOINT'  'configure'  'The URL of your OneFlow HTTP Endpoint API'                                      'M|text'
    'ONEAPP_JENKINS_OPENNEBULA_USERNAME'       'configure'  'The OpenNebula username used by Jenkins to deploy each component'               'M|text'
    'ONEAPP_JENKINS_OPENNEBULA_PASSWORD'       'configure'  'The password matching OPENNEBULA_USERNAME'                                      'M|password'
    'ONEAPP_JENKINS_OPENNEBULA_INSECURE'       'configure'  'Allow insecure connexion into the OpenNebula XML-RPC Endpoint API (skip TLS verification)'                  'O|boolean'
    'ONEAPP_JENKINS_AWS_ACCESS_KEY_ID'         'configure'  'S3 Storage access key. Same as used in the MinIO instance'                      'M|text'
    'ONEAPP_JENKINS_AWS_SECRET_ACCESS_KEY'     'configure'  'S3 Storage secret key. Same as used in the MinIO instance'                      'M|text'
)

ONEAPP_JENKINS_USERNAME="${ONEAPP_JENKINS_USERNAME:-admin}"
ONEAPP_JENKINS_PASSWORD="${ONEAPP_JENKINS_PASSWORD:-admin}"
ONEAPP_JENKINS_OPENNEBULA_INSECURE="${ONEAPP_JENKINS_OPENNEBULA_INSECURE:-YES}"


# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

DEP_PKGS="fontconfig openjdk-21-jre-headless gnupg software-properties-common gpg python3-pip"
DEP_PIP="boto3 botocore pyone==6.8.3 netaddr"
ANSIBLE_COLLECTIONS="amazon.aws kubernetes.core community.general"
CONSULT_ME_DIR="/var/lib/jenkins/consult_me/"



# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function Definitions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------

service_install()
{
    export DEBIAN_FRONTEND=noninteractive
    systemctl stop unattended-upgrades

    # packages
    install_pkg_deps DEP_PKGS

    # jenkins
    install_jenkins

    # pip modules
    install_pip_deps DEP_PIP

    # ansible and terraform
    install_ansible_terraform ANSIBLE_COLLECTIONS

    # jenkins admin user
    create_admin_user

    # plugins
    install_plugins_jenkins

    # pipelines
    import_pipelines

    # service metadata
    create_one_service_metadata

    # cleanup
    postinstall_cleanup

    msg info "INSTALLATION FINISHED"

    return 0
}

service_configure()
{
    export DEBIAN_FRONTEND=noninteractive

    # jenkins admin user
    update_admin_user

    # sshd
    generate_ssh_keys

    # credentials
    import_credentials

    systemctl restart jenkins

    msg info "CONFIGURATION FINISHED"
    return 0
}

service_bootstrap()
{
    return 0
}



# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Function Definitions
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------


install_pkg_deps()
{
    msg info "Run apt-get update"
    apt-get update

    msg info "Install required packages for Jenkins"
    if ! apt-get install -y ${!1} ; then
        msg error "Package(s) installation failed"
        exit 1
    fi
}

install_pip_deps()
{
    if [ -n ${1} ]; then
        msg info "Install required pip packages for Jenkins"
        if ! sudo -H -u jenkins bash -c "pip3 install ${!1}" ; then
            msg error "pip package(s) installation failed"
            exit 1
        fi
    fi
}

install_jenkins()
{
    msg info "Add jenkins .deb repository"
    wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
    chmod 644 /usr/share/keyrings/jenkins-keyring.asc
    echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" https://pkg.jenkins.io/debian-stable binary/ | tee /etc/apt/sources.list.d/jenkins.list > /dev/null
    apt-get update

    msg info "Install latest Jenkins LTS release"
    if ! apt-get install -y jenkins ; then
        msg error "jenkins installation failed"
        exit 1
    fi

    msg info "Define ulimits into new 'jenkins' user"
    cat > /etc/security/limits.d/30-jenkins.conf <<EOF
jenkins soft core unlimited
jenkins hard core unlimited
jenkins soft fsize unlimited
jenkins hard fsize unlimited
jenkins soft nofile 4096
jenkins hard nofile 8192
jenkins soft nproc 30654
jenkins hard nproc 30654
EOF

    msg info "Stablish Configuration as Code (CasC) path into the jenkins service"
    sudo -H -u jenkins bash -c "mkdir -m 700 /var/lib/jenkins/casc_configs/"
    sudo -H -u jenkins bash -c "mkdir -m 700 /var/lib/jenkins/consult_me/"

    mkdir /etc/systemd/system/jenkins.service.d
    cat > /etc/systemd/system/jenkins.service.d/override.conf <<EOF
[Service]
Environment="CASC_JENKINS_CONFIG=/var/lib/jenkins/casc_configs/"
EOF

    systemctl daemon-reload
    systemctl enable --now jenkins
}

install_ansible_terraform()
{
    msg info "Add ansible and terraform repositories"
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | \
    tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    chmod 644 /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
    tee /etc/apt/sources.list.d/hashicorp.list
    add-apt-repository --yes --update ppa:ansible/ansible
    apt-get update

    msg info "Install terraform and ansible"
    if ! apt-get install -y terraform ansible; then
        msg error "terraform and ansible installation failed"
        exit 1
    fi
    msg info "Install required ansible collections"
    if ! sudo -H -u jenkins bash -c "ansible-galaxy collection install ${!1}"; then
        msg error "instalation of ansible collections failed"
        exit 1
    fi
    # Add callback plugins
    cat <<EOT >> /etc/ansible/ansible.cfg

[defaults]
host_key_checking=false
stdout_callback=community.general.yaml
callbacks_enabled=ansible.posix.profile_tasks, ansible.posix.timer
EOT
    echo 'export PATH=$PATH:~/.local/bin' | sudo tee -a /var/lib/jenkins/.bashrc
    echo 'export ANSIBLE_COLLECTIONS_PATH=/var/lib/jenkins/.ansible/collections' | sudo tee -a /var/lib/jenkins/.bashrc
    sudo -H -u jenkins bash -c 'source /var/lib/jenkins/.bashrc'
}

create_admin_user()
{
    # Steps based on https://kevin-denotariis.medium.com/download-install-and-setup-jenkins-completely-from-bash-unlock-create-admin-user-and-more-debd3320414a
    msg info "Create admin user in jenkins"
    url=http://localhost:8080
    password=$(cat /var/lib/jenkins/secrets/initialAdminPassword)

    # ADMIN CREDENTIALS URL ENCODED USING PYTHON
    username=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "admin")
    new_password=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "admin")
    fullname=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "admin")
    email=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "hello@world.com")

    # GET THE CRUMB AND COOKIE
    cookie_jar="$(mktemp)"
    full_crumb=$(curl -u "admin:${password}" --cookie-jar "${cookie_jar}" ${url}/crumbIssuer/api/xml?xpath=concat\(//crumbRequestField,%22:%22,//crumb\))
    arr_crumb=(${full_crumb//:/ })
    only_crumb=$(echo ${arr_crumb[1]})

    # MAKE THE REQUEST TO CREATE AN ADMIN USER
    curl -X POST -u "admin:${password}" ${url}/setupWizard/createAdminUser \
            -H "Connection: keep-alive" \
            -H "Accept: application/json, text/javascript" \
            -H "X-Requested-With: XMLHttpRequest" \
            -H "${full_crumb}" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --cookie ${cookie_jar} \
            --data-raw "username=${username}&password1=${new_password}&password2=${new_password}&fullname=${fullname}&email=${email}&Jenkins-Crumb=${only_crumb}&json=%7B%22username%22%3A%20%22${username}%22%2C%20%22password1%22%3A%20%22${new_password}%22%2C%20%22%24redact%22%3A%20%5B%22password1%22%2C%20%22password2%22%5D%2C%20%22password2%22%3A%20%22${new_password}%22%2C%20%22fullname%22%3A%20%22${fullname}%22%2C%20%22email%22%3A%20%22${email}%22%2C%20%22Jenkins-Crumb%22%3A%20%22${only_crumb}%22%7D&core%3Aapply=&Submit=Save&json=%7B%22username%22%3A%20%22${username}%22%2C%20%22password1%22%3A%20%22${new_password}%22%2C%20%22%24redact%22%3A%20%5B%22password1%22%2C%20%22password2%22%5D%2C%20%22password2%22%3A%20%22${new_password}%22%2C%20%22fullname%22%3A%20%22${fullname}%22%2C%20%22email%22%3A%20%22${email}%22%2C%20%22Jenkins-Crumb%22%3A%20%22${only_crumb}%22%7D"
}

install_plugins_jenkins()
{
    # Steps based on https://kevin-denotariis.medium.com/download-install-and-setup-jenkins-completely-from-bash-unlock-create-admin-user-and-more-debd3320414a
    msg info "Install required jenkins plugins"
    url=http://localhost:8080
    url_urlEncoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "${url}")
    user=admin
    password=admin
    plugin_list=$(cat /etc/one-appliance/service.d/jenkins_plugins.txt | awk '{print "'"'"'" $0 "'"'"'"}' | paste -sd,)
    mapfile -t plugins_map < "/etc/one-appliance/service.d/jenkins_plugins.txt"

    # GET THE CRUMB AND COOKIE
    cookie_jar="$(mktemp)"
    full_crumb=$(curl -u "${user}:${password}" --cookie-jar "${cookie_jar}" ${url}/crumbIssuer/api/xml?xpath=concat\(//crumbRequestField,%22:%22,//crumb\))
    arr_crumb=(${full_crumb//:/ })
    only_crumb=$(echo ${arr_crumb[1]})

    msg info "Make the request to download and install required modules"
    curl -X POST -u "${user}:${password}" ${url}/pluginManager/installPlugins \
        -H 'Connection: keep-alive' \
        -H 'Accept: application/json, text/javascript, */*; q=0.01' \
        -H 'X-Requested-With: XMLHttpRequest' \
        -H "${full_crumb}" \
        -H 'Content-Type: application/json' \
        -H 'Accept-Language: en,en-US;q=0.9,it;q=0.8' \
        --cookie ${cookie_jar} \
        --data-raw "{'dynamicLoad':true,'plugins':[${plugin_list}],'Jenkins-Crumb':'${only_crumb}'}"

    msg info "Send the request to confirm the url for the WebUI"
    curl -X POST -u "${user}:${password}" ${url}/setupWizard/configureInstance \
        -H 'Connection: keep-alive' \
        -H 'Accept: application/json, text/javascript, */*; q=0.01' \
        -H 'X-Requested-With: XMLHttpRequest' \
        -H "${full_crumb}" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        -H 'Accept-Language: en,en-US;q=0.9,it;q=0.8' \
        --cookie ${cookie_jar} \
        --data-raw "rootUrl=${url_urlEncoded}%2F&Jenkins-Crumb=${only_crumb}&json=%7B%22rootUrl%22%3A%20%22${url_urlEncoded}%2F%22%2C%20%22Jenkins-Crumb%22%3A%20%22${only_crumb}%22%7D&core%3Aapply=&Submit=Save&json=%7B%22rootUrl%22%3A%20%22${url_urlEncoded}%2F%22%2C%20%22Jenkins-Crumb%22%3A%20%22${only_crumb}%22%7D"

    msg info "Waiting for plugins to be installed..."
    attempt_counter=0
    max_attempts=30

    while ! check_plugins_installed; do
    if [ ${attempt_counter} -eq ${max_attempts} ]; then
        echo "Max attempts reached. Some plugins might not be installed."
        exit 1
    fi

    attempt_counter=$((attempt_counter + 1))
    echo "Waiting for plugins to be installed... attempt ${attempt_counter}/${max_attempts}"
    sleep 10
    done

    msg info "All plugins are installed successfully."
}

check_plugins_installed() {
    installed_plugins=$(curl -s -u "${user}:${password}" "${url}/pluginManager/api/json?depth=1" -H 'Accept: application/json' | jq -r '.plugins[].shortName')
    for plugin in "${plugins_map[@]}"; do
    if ! echo "${installed_plugins}" | grep -q "^${plugin}$"; then
        echo "Plugin not installed yet: ${plugin}"
        return 1
    fi
    done
    return 0
}

import_pipelines(){
    msg info "Import starting jenkins pipelines"
    cp /etc/one-appliance/service.d/jobs.yaml /var/lib/jenkins/casc_configs/jobs.yaml
    chown jenkins:jenkins /var/lib/jenkins/casc_configs/jobs.yaml
    chmod u=r,go= /var/lib/jenkins/casc_configs/jobs.yaml
}

update_admin_user()
{
    msg info "Update admin username and password in jenkins"
    url=http://localhost:8080

    username=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "${ONEAPP_JENKINS_USERNAME}")
    password=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "${ONEAPP_JENKINS_PASSWORD}")
    fullname=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "${ONEAPP_JENKINS_USERNAME}")
    email=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "hello@world.com")

    # GET THE CRUMB AND COOKIE
    cookie_jar="$(mktemp)"
    full_crumb=$(curl -u "admin:admin" --cookie-jar "$cookie_jar" ${url}/crumbIssuer/api/xml?xpath=concat\(//crumbRequestField,%22:%22,//crumb\))
    arr_crumb=(${full_crumb//:/ })
    only_crumb=$(echo ${arr_crumb[1]})

    # MAKE THE REQUEST TO CREATE AN ADMIN USER
    curl -X POST -u "admin:admin" $url/setupWizard/createAdminUser \
        -H "Connection: keep-alive" \
        -H "Accept: application/json, text/javascript" \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "${full_crumb}" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --cookie ${cookie_jar} \
        --data-raw "username=${username}&password1=${password}&password2=${password}&fullname=${fullname}&email=${email}&Jenkins-Crumb=${only_crumb}&json=%7B%22username%22%3A%20%22${username}%22%2C%20%22password1%22%3A%20%22${password}%22%2C%20%22%24redact%22%3A%20%5B%22password1%22%2C%20%22password2%22%5D%2C%20%22password2%22%3A%20%22${password}%22%2C%20%22fullname%22%3A%20%22${fullname}%22%2C%20%22email%22%3A%20%22${email}%22%2C%20%22Jenkins-Crumb%22%3A%20%22${only_crumb}%22%7D&core%3Aapply=&Submit=Save&json=%7B%22username%22%3A%20%22${username}%22%2C%20%22password1%22%3A%20%22${password}%22%2C%20%22%24redact%22%3A%20%5B%22password1%22%2C%20%22password2%22%5D%2C%20%22password2%22%3A%20%22${password}%22%2C%20%22fullname%22%3A%20%22${fullname}%22%2C%20%22email%22%3A%20%22${email}%22%2C%20%22Jenkins-Crumb%22%3A%20%22${only_crumb}%22%7D"

    msg info "Generate admin token in jenkins and write it at ${CONSULT_ME_DIR}jenkins_tnlcm_token"
    another_cookie_jar="$(mktemp)"
    another_full_crumb=$(curl -u "${ONEAPP_JENKINS_USERNAME}:${ONEAPP_JENKINS_PASSWORD}" --cookie-jar "$another_cookie_jar" ${url}/crumbIssuer/api/xml?xpath=concat\(//crumbRequestField,%22:%22,//crumb\))

    jenkins_tnlcm_token=$(curl -u "${ONEAPP_JENKINS_USERNAME}:${ONEAPP_JENKINS_PASSWORD}" ${url}/me/descriptorByName/jenkins.security.ApiTokenProperty/generateNewToken \
        -H ${another_full_crumb} -s \
        --cookie ${another_cookie_jar} \
        --data 'newTokenName=TNLCMtoken' | jq -r '.data.tokenValue')

    echo "${jenkins_tnlcm_token}" > "${CONSULT_ME_DIR}jenkins_tnlcm_token"
    chown jenkins:jenkins "${CONSULT_ME_DIR}jenkins_tnlcm_token"
    chmod u=r,go= "${CONSULT_ME_DIR}jenkins_tnlcm_token"
}

generate_ssh_keys()
{
    msg info "Generate ssh keys for user jenkins and write them at ${CONSULT_ME_DIR}"
    sudo -H -u jenkins bash -c "ssh-keygen -t ed25519 -f /var/lib/jenkins/.ssh/id_ed25519 -N ''"
    sudo -H -u jenkins bash -c "cp /var/lib/jenkins/.ssh/id_ed25519* ${CONSULT_ME_DIR}"
    sudo -H -u jenkins bash -c "cat > /var/lib/jenkins/.ssh/config << EOF
Include ~/.ssh/config.d/*

Host *
  StrictHostKeyChecking no
  UserKnownHostsFile /dev/null
EOF"
}

import_credentials()
{
    cat > /var/lib/jenkins/casc_configs/credentials.yaml << EOF
credentials:
  system:
    domainCredentials:
      - credentials:
          - string:
              scope: GLOBAL
              id: "SSH_PRIVATE_KEY"
              secret: "$(cat /var/lib/jenkins/.ssh/id_ed25519)"
              description: "SSH private key to access VM components"
      - credentials:
          - string:
              scope: GLOBAL
              id: "ANSIBLE_VAULT_PASSWORD"
              secret: "$(echo ${ONEAPP_JENKINS_SITES_TOKEN} | xargs)"
              description: "Password to encrypt and decrypt the 6G-Sandbox-Sites repository files for your site using Ansible Vault"
      - credentials:
          - string:
              scope: GLOBAL
              id: "OPENNEBULA_ENDPOINT"
              secret: "$(echo ${ONEAPP_JENKINS_OPENNEBULA_ENDPOINT} | xargs)"
              description: "The URL of your OpenNebula XML-RPC Endpoint API (for example,'http://example.com:2633/RPC2')"
      - credentials:
          - string:
              scope: GLOBAL
              id: "OPENNEBULA_FLOW_ENDPOINT"
              secret: "$(echo ${ONEAPP_JENKINS_OPENNEBULA_FLOW_ENDPOINT} | xargs)"
              description: "The URL of your OneFlow HTTP Endpoint API (for example,'http://example.com:2474')"
      - credentials:
          - string:
              scope: GLOBAL
              id: "OPENNEBULA_USERNAME"
              secret: "$(echo ${ONEAPP_JENKINS_OPENNEBULA_USERNAME} | xargs)"
              description: "The OpenNebula username used to deploy each component (for example,'jenkins')"
      - credentials:
          - string:
              scope: GLOBAL
              id: "OPENNEBULA_PASSWORD"
              secret: "$(echo ${ONEAPP_JENKINS_OPENNEBULA_PASSWORD} | xargs)"
              description: "The OpenNebula password matching OPENNEBULA_USERNAME"
      - credentials:
          - string:
              scope: GLOBAL
              id: "OPENNEBULA_INSECURE"
              secret: "$(if [ \"${ONEAPP_JENKINS_OPENNEBULA_INSECURE}\" = \"YES\" ]; then echo true; else echo false; fi)"
              description: "Allow insecure connexion into the OpenNebula XML-RPC Endpoint API (skip TLS verification)"
      - credentials:
          - string:
              scope: GLOBAL
              id: "AWS_ACCESS_KEY_ID"
              secret: "$(echo ${ONEAPP_JENKINS_AWS_ACCESS_KEY_ID} | xargs)"
              description: "S3 Storage access key. Same as used in the MinIO instance"
      - credentials:
          - string:
              scope: GLOBAL
              id: "AWS_SECRET_ACCESS_KEY"
              secret: "$(echo ${ONEAPP_JENKINS_AWS_SECRET_ACCESS_KEY} | xargs)"
              description: "S3 Storage secret key. Same as used in the MinIO instance"
EOF
    chown jenkins:jenkins /var/lib/jenkins/casc_configs/credentials.yaml
    chmod u=r,go= /var/lib/jenkins/casc_configs/credentials.yaml
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}
