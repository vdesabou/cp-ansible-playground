#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/utils.sh

verify_installed "git"
verify_installed "ansible"
verify_installed "ansible-playbook"

if [ -z "$1" ]
then
    logerror "ERROR: No argument supplied. Version must be provided."
    exit 1
fi

export TAG=$1

if ! version_gt $TAG "5.3.0"; then
    logerror "ERROR: only versions from 5.3.1 are supported"
    exit 1
fi

GIT_BRANCH="$TAG-post"
ANSIBLE_VER=$(get_ansible_version)

# https://docs.confluent.io/ansible/current/ansible-download.html#download-ansible-for-ansible-2-11-or-higher-hosts
if version_gt $ANSIBLE_VER "2.10" && version_gt $TAG "6.9.9"
then
    log "Using ansible-galaxy to install cp-ansible"
    ansible-galaxy collection install confluent.platform:$TAG
else
    cd ${DIR}/..
    if [ ! -d ${DIR}/../cp-ansible ]
    then
        log "Getting cp-ansible from Github (branch $GIT_BRANCH)"
        git clone https://github.com/confluentinc/cp-ansible
        cd ${DIR}/../cp-ansible
        git checkout "${GIT_BRANCH}"

        # get last commit time unix timestamp for the branch
        # now=$(date +%s)
        # last_git_commit=$(git log --format=%ct | head -1)
        # elapsed_git_time=$((now-last_git_commit))
        # if [[ $elapsed_git_time -gt 604800 ]]
        # then
        #     log "####################################################"
        #     log "Skipping as last commit on this branch was more than 7 days ago: it was done $(displaytime $elapsed_git_time) ago."
        #     log "####################################################"
        #     exit 0
        # fi
    fi

    # copy custom files
    cp ${DIR}/../hosts.yml ${DIR}/../cp-ansible/
    cd ${DIR}/../cp-ansible
fi

docker-compose down -v
docker-compose up -d

log "Checking Ansible can connect over DOCKER."
ansible -i hosts.yml all -m ping

# https://docs.confluent.io/ansible/current/ansible-install.html
if version_gt $ANSIBLE_VER "2.10" && version_gt $TAG "6.9.9"
then
    export ANSIBLE_CONFIG=${DIR}/../ansible.cfg
    log "Run the confluent.platform.all playbook."
    retry ansible-playbook -i hosts.yml confluent.platform.all
else
    log "Run the all.yml playbook."
    retry ansible-playbook -i hosts.yml all.yml
fi

# ls /etc/systemd/system/
log "Stopping all services."
docker exec control-center systemctl stop confluent-control-center
ksqlservice="confluent-ksql"
if version_gt $TAG "5.4.10"; then
    ksqlservice="confluent-ksqldb"
fi
docker exec ksql-server systemctl stop $ksqlservice
docker exec rest-proxy systemctl stop confluent-kafka-rest
docker exec schema-registry systemctl stop confluent-schema-registry
docker exec connect systemctl stop confluent-kafka-connect
brokerservice="confluent-kafka"
if version_gt $TAG "5.3.10"; then
    brokerservice="confluent-server"
fi
docker exec broker1 systemctl stop $brokerservice
docker exec broker2 systemctl stop $brokerservice
docker exec broker3 systemctl stop $brokerservice
docker exec zookeeper1 systemctl stop confluent-zookeeper

df -h

docker system df

docker system prune -a -f

log "Creating new images from snapshot."
docker commit zookeeper1 vdesabou/cp-ansible-playground-zookeeper1:$TAG
docker commit broker1 vdesabou/cp-ansible-playground-broker1:$TAG
docker commit broker2 vdesabou/cp-ansible-playground-broker2:$TAG
docker commit broker3 vdesabou/cp-ansible-playground-broker3:$TAG
docker commit schema-registry vdesabou/cp-ansible-playground-schema-registry:$TAG
docker commit ksql-server vdesabou/cp-ansible-playground-ksql-server:$TAG
docker commit rest-proxy vdesabou/cp-ansible-playground-rest-proxy:$TAG
docker commit connect vdesabou/cp-ansible-playground-connect:$TAG
docker commit control-center vdesabou/cp-ansible-playground-control-center:$TAG


log "Pushing images to Docker Hub."
docker push vdesabou/cp-ansible-playground-zookeeper1:$TAG
docker push vdesabou/cp-ansible-playground-broker1:$TAG
docker push vdesabou/cp-ansible-playground-broker2:$TAG
docker push vdesabou/cp-ansible-playground-broker3:$TAG
docker push vdesabou/cp-ansible-playground-schema-registry:$TAG
docker push vdesabou/cp-ansible-playground-ksql-server:$TAG
docker push vdesabou/cp-ansible-playground-rest-proxy:$TAG
docker push vdesabou/cp-ansible-playground-connect:$TAG
docker push vdesabou/cp-ansible-playground-control-center:$TAG
