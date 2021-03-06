#!/bin/bash

set -e

echo "-----> `date`: Upload stemcell"
bosh -n upload-stemcell "https://bosh.io/d/stemcells/bosh-warden-boshlite-ubuntu-trusty-go_agent?v=3445.7" \
  --sha1 4c0670b318ca4c394e72037e05f49cc14d369636 \
  --name bosh-warden-boshlite-ubuntu-trusty-go_agent \
  --version 3445.7

echo "-----> `date`: Delete previous deployment"
bosh -n -d cockroachdb-broker delete-deployment --force
rm -f broker-creds.yml

echo "-----> `date`: Deploy"
( set -e; cd ./../..;
  bosh -n -d cockroachdb-broker deploy ./manifests/broker.yml -o ./manifests/dev.yml \
  -v director_ip=192.168.50.6 \
  -v director_client=admin \
  -v director_client_secret=$(bosh int ~/workspace/deployments/vbox/creds.yml --path /admin_password) \
  --var-file director_ssl.ca=<(bosh int ~/workspace/deployments/vbox/creds.yml --path /director_ssl/ca) \
  -v broker_name=cockroachdb-broker \
  -v srv_id=cockroachdb \
  -v srv_name=CockroachDB \
  -v srv_description=CockroachDB \
  --var-file si_manifest=<(cat examples/cockroachdb/service-instance.yml|base64) \
  -v si_params=null \
  --var-file sb_manifest=<(cat examples/cockroachdb/service-binding.yml|base64) \
  --var-file sb_params=<(cat examples/cockroachdb/service-binding-params.yml|base64) \
  --vars-store ./examples/cockroachdb/creds.yml )

echo "-----> `date`: Use SB CLI"
export SB_BROKER_URL=http://$(bosh -d cockroachdb-broker is --column ips|head -1|tr -d '[:space:]'):8080
export SB_BROKER_USERNAME=broker
export SB_BROKER_PASSWORD=$(bosh int creds.yml --path /broker_password)

sb-cli services

echo "-----> `date`: Delete old service instances"
sb-cli delete-service-instance test1
sb-cli delete-service-instance test2

echo "-----> `date`: Create service instances"
sb-cli create-service-instance test1
sb-cli create-service-instance test2

echo "-----> `date`: Check on service instances"
bosh -d service-instance-test1 manifest
bosh -d service-instance-test2 manifest

echo "-----> `date`: Create bindings"
sb-cli create-service-binding test2 --id=binding1
sb-cli create-service-binding test2 --id=binding2 -p read_only=true
sb-cli create-service-binding test1 --id=binding3

# todo check that binding is readonly

echo "-----> `date`: Delete bindings"
sb-cli delete-service-binding binding1 test2
sb-cli delete-service-binding binding2 test2
sb-cli delete-service-binding binding3 test1

echo "-----> `date`: Delete service instances"
sb-cli delete-service-instance test1
sb-cli delete-service-instance test2

echo "-----> `date`: Delete deployments"
bosh -n -d cockroachdb-broker delete-deployment
rm -f broker-creds.yml

echo "-----> `date`: Done"
