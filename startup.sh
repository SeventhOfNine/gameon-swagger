#!/bin/bash

# Configure our link to etcd based on shared volume with secret
if [ ! -z "$ETCD_SECRET" ]; then
  echo "Configuring for secure etcd"
  . /data/primordial/setup.etcd.sh /data/primordial $ETCD_SECRET
else
  echo "Using local env for any etcd"
fi

# Configure amalgam8 for this container
export A8_SERVICE=swagger:v1
export A8_ENDPOINT_PORT=8080
export A8_ENDPOINT_TYPE=http

if [ "$ETCDCTL_ENDPOINT" != "" ]; then
  echo Setting up etcd...
  echo "** Testing etcd is accessible"
  etcdctl --debug ls
  RC=$?

  while [ $RC -ne 0 ]; do
    sleep 15
    # recheck condition
    echo "** Re-testing etcd connection"
    etcdctl --debug ls
    RC=$?
  done
  echo "etcdctl returned sucessfully, continuing"

  export LOGSTASH_ENDPOINT=$(etcdctl get /logstash/endpoint)
  export A8_REGISTRY_URL=$(etcdctl get /amalgam8/registryUrl)
  export A8_CONTROLLER_URL=$(etcdctl get /amalgam8/controllerUrl)
  export A8_CONTROLLER_POLL=$(etcdctl get /amalgam8/controllerPoll)
  JWT=$(etcdctl get /amalgam8/jwt)    

  # Softlayer needs a logstash endpoint so we set up the server
  # to run in the background and the primary task is running the
  # forwarder. In ICS, Liberty is the primary task so we need to
  # run it in the foreground
  if [ "$LOGSTASH_ENDPOINT" != "" ]; then
     echo Starting nginx in the background...
     if [ -z "$A8_REGISTRY_URL" ]; then 
       echo Running without a8.
       #no a8, just run server.
       nginx -c /etc/nginx/nginx.conf
     else
       #a8, configure security, and run via sidecar.
       if [ ! -z "$JWT" ]; then     
         echo Running a8 with security.
         export A8_REGISTRY_TOKEN=$JWT
         export A8_CONTROLLER_TOKEN=$JWT
       else
         echo Running a8 with no security.
       fi
       a8sidecar --proxy --register nginx -c /etc/nginx/nginx.conf
    fi  
    echo Starting the logstash forwarder...
    sed -i s/PLACEHOLDER_LOGHOST/${LOGSTASH_ENDPOINT}/g /opt/forwarder.conf
    cd /opt
    chmod +x ./forwarder
    etcdctl get /logstash/cert > logstash-forwarder.crt
    etcdctl get /logstash/key > logstash-forwarder.key
    sleep 0.5
    ./forwarder --config ./forwarder.conf
  else
    echo Launching nginx with  logging to standard out
    nginx -c /etc/nginx/nginx-nolog.conf
  fi
else
  echo No logging host set. Running nginx to standard out...
  nginx -c /etc/nginx/nginx-nolog.conf
fi
