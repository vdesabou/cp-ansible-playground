#!/bin/bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
source ${DIR}/utils.sh

verify_installed "git"
verify_installed "ansible"
verify_installed "ansible-playbook"

if [ -z "$1" ]
  then
    echo "ERROR: No argument supplied. Version must be provided."
    exit 1
fi

export TAG=$1

cd ${DIR}/..
if [ ! -d ${DIR}/../cp-ansible ]
then
    log "INFO: Getting cp-ansible from Github."
    git clone https://github.com/confluentinc/cp-ansible
fi

# copy custom files
cp ${DIR}/../hosts.yml ${DIR}/../cp-ansible/

docker-compose down -v
docker-compose up -d

cd ${DIR}/../cp-ansible

log "INFO: Checking Ansible can connect over DOCKER."
ansible -i hosts.yml all -m ping

exit 0
log "INFO: Run the all.yml playbook."
ansible-playbook -i hosts.yml all.yml

# if it fails, try to re-run this command
# ansible-playbook -vvvv -i hosts.yml all.yml


# ls /etc/systemd/system/
log "INFO: Stopping all services."
docker exec control-center systemctl stop confluent-control-center
docker exec ksql-server systemctl stop confluent-ksql
docker exec rest-proxy systemctl stop confluent-kafka-rest
docker exec schema-registry systemctl stop confluent-schema-registry
docker exec connect systemctl stop confluent-kafka-connect
docker exec broker1 systemctl stop confluent-kafka
docker exec broker2 systemctl stop confluent-kafka
docker exec broker3 systemctl stop confluent-kafka
docker exec zookeeper1 systemctl stop confluent-zookeeper

log "INFO: Creating new images from snapshot."
docker commit zookeeper1 vdesabou/cp-ansible-playground-zookeeper1:$TAG
docker commit broker1 vdesabou/cp-ansible-playground-broker1:$TAG
docker commit broker2 vdesabou/cp-ansible-playground-broker2:$TAG
docker commit broker3 vdesabou/cp-ansible-playground-broker3:$TAG
docker commit schema-registry vdesabou/cp-ansible-playground-schema-registry:$TAG
docker commit ksql-server vdesabou/cp-ansible-playground-ksql-server:$TAG
docker commit rest-proxy vdesabou/cp-ansible-playground-rest-proxy:$TAG
docker commit connect vdesabou/cp-ansible-playground-connect:$TAG
docker commit control-center vdesabou/cp-ansible-playground-control-center:$TAG


log "INFO: Pushing images to Docker Hub."
docker push vdesabou/cp-ansible-playground-zookeeper1:$TAG
docker push vdesabou/cp-ansible-playground-broker1:$TAG
docker push vdesabou/cp-ansible-playground-broker2:$TAG
docker push vdesabou/cp-ansible-playground-broker3:$TAG
docker push vdesabou/cp-ansible-playground-schema-registry:$TAG
docker push vdesabou/cp-ansible-playground-ksql-server:$TAG
docker push vdesabou/cp-ansible-playground-rest-proxy:$TAG
docker push vdesabou/cp-ansible-playground-connect:$TAG
docker push vdesabou/cp-ansible-playground-control-center:$TAG