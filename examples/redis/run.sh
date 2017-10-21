#!/bin/bash

set -e

example_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $example_dir/../..

director_creds_file=${director_creds_file:-~/workspace/deployments/vbox/creds.yml}
if [[ ! -f $director_creds_file ]]; then
  echo "Missing file \$director_creds_file = $director_creds_file"
  exit 1
fi
if [[ "$(which sb-cli)X" == "X" ]]; then
  echo "Please install sb-cli from https://github.com/cppforlife/sb-cli"
  exit 1
fi

if [[ "${skip_stemcell_upload}X" == "X" ]]; then
  echo "-----> `date`: Upload stemcell"
  bosh -n upload-stemcell "https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent?v=3468" \
    --sha1 7001de6d7db5493d093ebf0b2a9c3733386e2e89 \
    --name bosh-warden-boshlite-ubuntu-trusty-go_agent \
    --version 3468
fi

echo "-----> `date`: Delete previous deployment"
bosh -n -d redis-broker delete-deployment --force
broker_creds_file=$example_dir/broker-creds.yml
rm -f $broker_creds_file

broker_name=redis-broker
si_manifest_url=https://raw.githubusercontent.com/cloudfoundry-community/redis-boshrelease/master/manifests/redis.yml

echo "-----> `date`: Deploy"
( set -e
  broker_creds_file=$example_dir/broker-creds.yml
  bosh -n -d $broker_name deploy ./manifests/broker.yml -o ./manifests/dev.yml \
  -v director_ip=192.168.50.6 \
  -v director_client=admin \
  -v director_client_secret=$(bosh int $director_creds_file --path /admin_password) \
  --var-file director_ssl.ca=<(bosh int $director_creds_file --path /director_ssl/ca) \
  -v broker_name=redis-broker \
  -v srv_id=redis \
  -v srv_name="Redis" \
  -v srv_description="Redis cluster" \
  --var-file si_manifest=<(wget -O- ${si_manifest_url}|bosh int - -o $example_dir/fixes.yml|base64) \
  -v si_params=null \
  -v sb_manifest=null \
  -v sb_params=null \
  --vars-store $broker_creds_file )

echo "-----> `date`: Use SB CLI"
export SB_BROKER_URL=http://$(bosh -d $broker_name is --column ips|head -1|tr -d '[:space:]'):8080
export SB_BROKER_USERNAME=broker
export SB_BROKER_PASSWORD=$(bosh int $broker_creds_file --path /broker_password)

sb-cli services

echo "-----> `date`: Delete old service instances"
sb-cli delete-service-instance test1

echo "-----> `date`: Create service instances"
sb-cli create-service-instance test1

echo "-----> `date`: Check on service instances"
bosh -d service-instance-test1 manifest

echo "-----> `date`: Delete service instances"
sb-cli delete-service-instance test1

echo "-----> `date`: Delete deployments"
bosh -n -d $broker_name delete-deployment
rm -f broker-creds.yml

echo "-----> `date`: Done"
