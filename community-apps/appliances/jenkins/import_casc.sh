#!/bin/bash

import_pipelines_casc(){
    msg info "Import default 6G-Sandbox pipelines as ConfigurationAsCode"
    cp /etc/one-appliance/service.d/jobs.yaml /var/lib/jenkins/casc_configs/jobs.yaml
    cat > /var/lib/jenkins/casc_configs/jobs.yaml << 'EOF'
jobs:
  - script: >
      pipelineJob('TN_DEPLOY') {
        parameters {
          stringParam('TN_ID', '', 'Trial Network Identifier. Valid characters are A-Z, a-z, 0-9 and underscore _. MANDATORY')
          stringParam('COMPONENT_TYPE', '', '6G Library Component type. MANDATORY')
          stringParam('CUSTOM_NAME', '', 'Custom name for the component inside the Trial Network. Valid characters are A-Z, a-z, 0-9 and underscore _. MANDATORY except for tn_init (including tn_vxlan and tn_bastion)')
          stringParam('DEPLOYMENT_SITE', '', 'Site where the deployment is being made. E.g. uma, athens, fokus, oulu... MANDATORY')
          stringParam('TNLCM_CALLBACK', 'http://tnlcm-ip:5000/tnlcm/callback/', 'URL of the TNLCM to notify the results. MANDATORY')
          stringParam('LIBRARY_URL', 'https://github.com/6G-SANDBOX/6G-Library.git', '6G-Library repository HTTPS URL. Leave it as-is unless you want to test your own fork')
          stringParam('LIBRARY_BRANCH', 'refs/tags/v0.4.0', 'LIBRARY_URL checkout to use. Valid inputs can be refs/heads/<branchName>, refs/tags/<tagName> or <commitId>. Leave it as-is unless you want to test alternative releases/branches/commits.')
          stringParam('SITES_URL', 'https://github.com/6G-SANDBOX/6G-Sandbox-Sites.git', '6G-Library-Sites repository HTTP URL. Leave it as-is unless you want to test your own fork')
          stringParam('SITES_BRANCH', 'refs/heads/main', 'SITES_URL checkout to use. Valid inputs can be refs/heads/<branchName>, refs/tags/<tagName> or <commitId>. Leave it as-is unless you want to test alternative releases/branches/commits.')
          booleanParam('DEBUG', false, 'Enable DEBUG. Files will not be purged after the pipeline execution. WARNING: You need to manually delete the Jenkins Workspace after using this feature.')
          base64File{
            name('FILE')
            description('YAML file that contains the public variables needed to deploy the component')
          }
        }
        definition {
          cpsScm {
            scm {
              git {
                remote {
                  url('^${LIBRARY_URL}')
                }
                branch('^${LIBRARY_BRANCH}')
              }
            }
            scriptPath('.global/pac/TN_DEPLOY.groovy')
          }
        }
      }
  - script: >
      pipelineJob('TN_DESTROY') {
        parameters {
          stringParam('TN_ID', '', 'Trial Network Identifier. MANDATORY')
          stringParam('DEPLOYMENT_SITE', '', 'Site where the deployment is being made. E.g. uma, athens, fokus, oulu... MANDATORY')
          stringParam('TNLCM_CALLBACK', 'http://tnlcm-ip:5000/tnlcm/callback/', 'URL of the TNLCM to notify the results. MANDATORY')
          stringParam('LIBRARY_URL', 'https://github.com/6G-SANDBOX/6G-Library.git', '6G-Library repository HTTPS URL. Leave it as-is unless you want to test your own fork')
          stringParam('LIBRARY_BRANCH', 'refs/tags/v0.4.0', 'LIBRARY_URL checkout to use. Valid inputs can be refs/heads/<branchName>, refs/tags/<tagName> or <commitId>. Default value can purge TNs from previous 6G-Library version.')
          stringParam('SITES_URL', 'https://github.com/6G-SANDBOX/6G-Sandbox-Sites.git', '6G-Library-Sites repository HTTP URL. Leave it as-is unless you want to test your own fork')
          stringParam('SITES_BRANCH', 'refs/heads/main', 'SITES_URL checkout to use. Valid inputs can be refs/heads/<branchName>, refs/tags/<tagName> or <commitId>. Leave it as-is unless you want to test alternative releases/branches/commits.')
          booleanParam('DEBUG', false, 'Enable DEBUG. Files will not be purged after the pipeline execution')
        }
        definition {
          cpsScm {
            scm {
              git {
                remote {
                  url('^${LIBRARY_URL}')
                }
                branch('^${LIBRARY_BRANCH}')
              }
            }
            scriptPath('.global/pac/TN_DESTROY.groovy')
          }
        }
      }
EOF
    chown jenkins:jenkins /var/lib/jenkins/casc_configs/jobs.yaml
    chmod u=r,go= /var/lib/jenkins/casc_configs/jobs.yaml
}

import_credentials_casc() {
    msg info "Import jenkins credentials as ConfigurationAsCode"
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

configure_jenkins_bashrc() {
    msg info "Add environment variables to jenkins user for debugging purposes"

    local ENV_VARS="
### Jenkins Environment Variables
export OPENNEBULA_USERNAME=\"${ONEAPP_JENKINS_OPENNEBULA_USERNAME}\"
export OPENNEBULA_PASSWORD=\"${ONEAPP_JENKINS_OPENNEBULA_PASSWORD}\"
export OPENNEBULA_ENDPOINT=\"${ONEAPP_JENKINS_OPENNEBULA_ENDPOINT}\"
export OPENNEBULA_FLOW_ENDPOINT=\"${ONEAPP_JENKINS_OPENNEBULA_FLOW_ENDPOINT}\"
export OPENNEBULA_INSECURE=\"${ONEAPP_JENKINS_OPENNEBULA_INSECURE}\"
export AWS_ACCESS_KEY_ID=\"${ONEAPP_JENKINS_AWS_ACCESS_KEY_ID}\"
export AWS_SECRET_ACCESS_KEY=\"${ONEAPP_JENKINS_AWS_SECRET_ACCESS_KEY}\"

### Sample commands
# ansible-playbook --vault-password-file /var/lib/jenkins/superisecurevaultpassword -i localhost, -e workspace=/var/lib/jenkins/workspace/TN_DESTROY -e deployment_site=uma -e tn_id=canary -e tnlcm_callback=http://localhost:1234 /var/lib/jenkins/workspace/TN_DESTROY/.global/cac/tn_destroy.yaml
# ansible-playbook --vault-password-file /var/lib/jenkins/superisecurevaultpassword -i localhost, -e workspace=/var/lib/jenkins/workspace/TN_DEPLOY -e tn_id=b1w5 -e component_type=oneKE -e custom_name=cluster -e entity_name=oneKE-cluster -e deployment_site=uma -e tnlcm_callback=http://10.11.28.148:5000/tnlcm/callback -e debug=true /var/lib/jenkins/workspace/TN_DEPLOY/oneKE/code/component_playbook.yaml"

    # Avoid duplicate entries
    if ! grep -q "OPENNEBULA_USERNAME" "/var/lib/jenkins/.bashrc"; then
        echo "${ENV_VARS}" >> "/var/lib/jenkins/.bashrc"
        echo "${ONEAPP_JENKINS_SITES_TOKEN}" > "/var/lib/jenkins/superisecurevaultpassword"
    fi
}
