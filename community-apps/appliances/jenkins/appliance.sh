#!/usr/bin/env bash

set -o errexit -o pipefail

# ------------------------------------------------------------------------------
# Global variables
# ------------------------------------------------------------------------------

ONEAPP_JENKINS_USERNAME="${ONEAPP_JENKINS_USERNAME:-admin}"
ONEAPP_JENKINS_OPENNEBULA_INSECURE="${ONEAPP_JENKINS_OPENNEBULA_INSECURE:-YES}"

DEP_PKGS="fontconfig openjdk-21-jre-headless gnupg software-properties-common gpg python3-pip ruby-dev"
DEP_RUBY="opennebula-cli"
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
    install_deps

    # jenkins
    install_jenkins

    # pip modules for jenkins user
    install_pip_deps

    # ansible and terraform
    install_ansible_terraform

    # jenkins admin user
    create_admin_user

    # plugins
    install_plugins_jenkins

    # import pipelines casc
    source /etc/one-appliance/service.d/import_casc.sh
    import_pipelines_casc

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

    # import credentials casc
    source /etc/one-appliance/service.d/import_casc.sh
    import_credentials_casc

    configure_jenkins_bashrc

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


install_deps()
{
    msg info "Run apt-get update"
    apt-get update

    msg info "Install required .deb packages"
    wait_for_dpkg_lock_release
    if ! apt-get install -y ${DEP_PKGS} ; then
        msg error "Package(s) installation failed"
        exit 1
    fi

    if [ -n "${DEP_RUBY}" ]; then
        msg info "Install required ruby gems"
        if ! gem install ${DEP_RUBY} ; then
            msg error "ruby gem(s) installation failed"
            exit 1
        fi
    fi
}

install_pip_deps()
{
    if [ -n "${DEP_PIP}" ]; then
        msg info "Install required pip packages for Jenkins"
        if ! sudo -H -u jenkins bash -c "pip3 install ${DEP_PIP}" ; then
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
    if ! sudo -H -u jenkins bash -c "ansible-galaxy collection install ${ANSIBLE_COLLECTIONS}"; then
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

    msg info "URL encode admin credentials using python"
    username=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "admin")
    new_password=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "admin")
    fullname=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "admin")
    email=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "hello@world.com")

    msg info "Get crumb and cookie for Jenkins API"
    cookie_jar="$(mktemp)"
    msg info "Variable cookie_jar set to ${cookie_jar}"
    full_crumb=$(curl -u "admin:${password}" --cookie-jar "${cookie_jar}" ${url}/crumbIssuer/api/xml?xpath=concat\(//crumbRequestField,%22:%22,//crumb\))
    msg info "Variable full_crumb set to ${full_crumb}"
    arr_crumb=(${full_crumb//:/ })
    msg info "Variable arr_crumb set to ${arr_crumb[0]}"
    only_crumb="$(echo ${arr_crumb[1]})"
    msg info "Variable only_crumb set to ${only_crumb}"

    msg info "Send API request to create the 'admin' user"
    curl -X POST -u "admin:${password}" ${url}/setupWizard/createAdminUser \
            -H "Connection: keep-alive" \
            -H "Accept: application/json, text/javascript" \
            -H "X-Requested-With: XMLHttpRequest" \
            -H "${full_crumb}" \
            -H "Content-Type: application/x-www-form-urlencoded" \
            --cookie "${cookie_jar}" \
            --data-raw "username=${username}&password1=${new_password}&password2=${new_password}&fullname=${fullname}&email=${email}&Jenkins-Crumb=${only_crumb}&json=%7B%22username%22%3A%20%22${username}%22%2C%20%22password1%22%3A%20%22${new_password}%22%2C%20%22%24redact%22%3A%20%5B%22password1%22%2C%20%22password2%22%5D%2C%20%22password2%22%3A%20%22${new_password}%22%2C%20%22fullname%22%3A%20%22${fullname}%22%2C%20%22email%22%3A%20%22${email}%22%2C%20%22Jenkins-Crumb%22%3A%20%22${only_crumb}%22%7D&core%3Aapply=&Submit=Save&json=%7B%22username%22%3A%20%22${username}%22%2C%20%22password1%22%3A%20%22${new_password}%22%2C%20%22%24redact%22%3A%20%5B%22password1%22%2C%20%22password2%22%5D%2C%20%22password2%22%3A%20%22${new_password}%22%2C%20%22fullname%22%3A%20%22${fullname}%22%2C%20%22email%22%3A%20%22${email}%22%2C%20%22Jenkins-Crumb%22%3A%20%22${only_crumb}%22%7D"
}

install_plugins_jenkins()
{
    # Steps based on https://kevin-denotariis.medium.com/download-install-and-setup-jenkins-completely-from-bash-unlock-create-admin-user-and-more-debd3320414a
    msg info "Install required jenkins plugins"
    url=http://localhost:8080
    url_urlEncoded=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "${url}")
    user="admin"
    password="admin"
    plugin_list=$(cat /etc/one-appliance/service.d/jenkins_plugins.txt | awk '{print "'"'"'" $0 "'"'"'"}' | paste -sd,)
    mapfile -t plugins_map < "/etc/one-appliance/service.d/jenkins_plugins.txt"

    msg info "Get crumb and cookie for Jenkins API"
    cookie_jar="$(mktemp)"
    msg info "Variable cookie_jar set to ${cookie_jar}"
    full_crumb=$(curl -u "${user}:${password}" --cookie-jar "${cookie_jar}" ${url}/crumbIssuer/api/xml?xpath=concat\(//crumbRequestField,%22:%22,//crumb\))
    msg info "Variable full_crumb set to ${full_crumb}"
    arr_crumb=(${full_crumb//:/ })
    msg info "Variable arr_crumb set to ${arr_crumb[0]}"
    only_crumb=$(echo ${arr_crumb[1]})

    msg info "Send API request to download and install the required plugins"
    curl -X POST -u "${user}:${password}" ${url}/pluginManager/installPlugins \
        -H 'Connection: keep-alive' \
        -H 'Accept: application/json, text/javascript, */*; q=0.01' \
        -H 'X-Requested-With: XMLHttpRequest' \
        -H "${full_crumb}" \
        -H 'Content-Type: application/json' \
        -H 'Accept-Language: en,en-US;q=0.9,it;q=0.8' \
        --cookie ${cookie_jar} \
        --data-raw "{'dynamicLoad':true,'plugins':[${plugin_list}],'Jenkins-Crumb':'${only_crumb}'}"

    # TODO: probably incorrect, as warning appears afterwards
    msg info "Send API request to confirm the WebUI URL"
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

update_admin_user()
{
    msg info "Update admin username and password in jenkins"
    url=http://localhost:8080

    msg info "URL encode admin credentials using python"
    username=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "${ONEAPP_JENKINS_USERNAME}")
    password=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "${ONEAPP_JENKINS_PASSWORD}")
    fullname=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "${ONEAPP_JENKINS_USERNAME}")
    email=$(python3 -c "import urllib.parse; print(urllib.parse.quote(input(), safe=''))" <<< "hello@world.com")

    msg info "Get crumb and cookie for Jenkins API"
    cookie_jar="$(mktemp)"
    msg info "Variable cookie_jar set to ${cookie_jar}"
    full_crumb=$(curl -u "admin:admin" --cookie-jar "$cookie_jar" ${url}/crumbIssuer/api/xml?xpath=concat\(//crumbRequestField,%22:%22,//crumb\))
    msg info "Variable full_crumb set to ${full_crumb}"
    arr_crumb=(${full_crumb//:/ })
    msg info "Variable arr_crumb set to ${arr_crumb[0]}"
    only_crumb="$(echo ${arr_crumb[1]})"

    # MAKE THE REQUEST TO CREATE AN ADMIN USER
    msg info "Send API request to create another Admin user"
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
    
    msg info "Allow SSH access to the jenkins Linux user with the Jenkins Admin Password"
    echo "jenkins:${ONEAPP_JENKINS_PASSWORD}" | chpasswd
    cat > /etc/ssh/sshd_config.d/jenkins.conf << 'EOF'
Match User jenkins
    PasswordAuthentication yes
EOF
    systemctl restart sshd
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

wait_for_dpkg_lock_release()
{
  local lock_file="/var/lib/dpkg/lock-frontend"
  local timeout=600
  local interval=5

  for ((i=0; i<timeout; i+=interval)); do
    if ! lsof "${lock_file}" &>/dev/null; then
      return 0
    fi
    msg info "Could not get lock ${lock_file} due to unattended-upgrades. Retrying in ${interval} seconds..."
    sleep "${interval}"
  done

  msg error "Error: 10m timeout without ${lock_file} being released by unattended-upgrades"
  exit 1
}

postinstall_cleanup()
{
    msg info "Delete cache and stored packages"
    apt-get autoclean
    apt-get autoremove
    rm -rf /var/lib/apt/lists/*
}
