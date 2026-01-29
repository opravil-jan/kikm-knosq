#!/bin/bash
# init-cluster.sh
set -euo pipefail

log() {
  # Usage: log "PREFIX" "message"
  printf '[%s] %s\n' "$1" "$2"
}

# Funkce pro kontrolu, zda uzel odpovídá
wait_for_mongo() {
  local host="$1"
  local port="$2"
  until mongosh --host "$host" --port "$port" --eval 'db.runCommand({ping:1})' &>/dev/null; 
    do
      log "---" "Node $host:$port is not responding yet, waiting..."
      sleep 2
    done
}

if [ "${CLUSTER_INIT_ENABLED:-1}" -eq 0 ]; then
  log "SKIP" "Cluster already initialized. Exiting."
  exit 0
fi

log "BOOT" "Waiting for mongos routers..."
wait_for_mongo "mongos-01.femoz.net" 27017
wait_for_mongo "mongos-02.femoz.net" 27017

log "DB" "Creating users"
mongosh --host mongodb.femoz.net --port 27017 -u cluster-admin -p gaetaiNgaisou6eilahmoS6chahr3ohf --authenticationDatabase admin --quiet /docker-entrypoint-initdb.d/05-db-users.js

log "MONGOS" "Adding shards to cluster"
mongosh --host mongodb.femoz.net --port 27017 -u ${INIT_CLUSTER_ADMIN_USERNAME} -p ${INIT_CLUSTER_ADMIN_PASSWORD} --authenticationDatabase ${INIT_CLUSTER_ADMIN_AUTHENTICATION_DATABASE} --quiet /docker-entrypoint-initdb.d/03-mongos-add-shards.js

log "DB" "Creating collections + validators"
mongosh --host mongodb.femoz.net --port 27017 -u ${INIT_CLUSTER_ADMIN_USERNAME} -p ${INIT_CLUSTER_ADMIN_PASSWORD} --authenticationDatabase ${INIT_CLUSTER_ADMIN_AUTHENTICATION_DATABASE} --quiet /docker-entrypoint-initdb.d/04-db-collections-validators.js

log "DB" "Enabling sharding"
mongosh --host mongodb.femoz.net --port 27017 -u ${INIT_CLUSTER_ADMIN_USERNAME} -p ${INIT_CLUSTER_ADMIN_PASSWORD} --authenticationDatabase ${INIT_CLUSTER_ADMIN_AUTHENTICATION_DATABASE} --quiet /docker-entrypoint-initdb.d/06-db-enable-sharding.js

log "IMPORT" "Importing data into the cluster"
mongoimport \
  --host mongodb.femoz.net \
  --port 27017 \
  --db video_watch_time \
  --username ${VIDEO_WATCH_TIME_USERNAME} \
  --password ${VIDEO_WATCH_TIME_PASSWORD} \
  --authenticationDatabase ${VIDEO_WATCH_TIME_AUTHENTICATION_DATABASE} \
  --collection devices \
  --file /docker-entrypoint-initdb.d/data/devices.json \
  --jsonArray \
  --stopOnError \
  --verbose

mongoimport \
  --host mongodb.femoz.net \
  --port 27017 \
  --db video_watch_time \
  --username ${VIDEO_WATCH_TIME_USERNAME} \
  --password ${VIDEO_WATCH_TIME_PASSWORD} \
  --authenticationDatabase ${VIDEO_WATCH_TIME_AUTHENTICATION_DATABASE} \
  --collection viewers \
  --file /docker-entrypoint-initdb.d/data/viewers.json \
  --jsonArray \
  --stopOnError \
  --verbose

log "DONE" "Cluster initialization completed successfully."
