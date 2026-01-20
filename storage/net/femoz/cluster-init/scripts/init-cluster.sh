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

log "BOOT" "Waiting for config servers..."
wait_for_mongo "config-server-01.femoz.net" 27019
wait_for_mongo "config-server-02.femoz.net" 27019
wait_for_mongo "config-server-03.femoz.net" 27019

log "CONFIG" "Initializing config replica set"
mongosh --host config-server-01.femoz.net --port 27019 --quiet /docker-entrypoint-initdb.d/01-config-rs-init.js

log "BOOT" "Waiting for shard-01 nodes..."
wait_for_mongo "shard-01-a.femoz.net" 27018
wait_for_mongo "shard-01-b.femoz.net" 27018
wait_for_mongo "shard-01-c.femoz.net" 27018

log "SHARD-01" "Initializing shard-01 replica set"
mongosh --host shard-01-a.femoz.net --port 27018 --quiet /docker-entrypoint-initdb.d/02-shard-01-rs-init.js

log "BOOT" "Waiting for shard-02 nodes..."
wait_for_mongo "shard-02-a.femoz.net" 27018
wait_for_mongo "shard-02-b.femoz.net" 27018
wait_for_mongo "shard-02-c.femoz.net" 27018

log "SHARD-02" "Initializing shard-02 replica set"
mongosh --host shard-02-a.femoz.net --port 27018 --quiet /docker-entrypoint-initdb.d/02-shard-02-rs-init.js

log "BOOT" "Waiting for shard-03 nodes..."
wait_for_mongo "shard-03-a.femoz.net" 27018
wait_for_mongo "shard-03-b.femoz.net" 27018
wait_for_mongo "shard-03-c.femoz.net" 27018

log "SHARD-03" "Initializing shard-03 replica set"
mongosh --host shard-03-a.femoz.net --port 27018 --quiet /docker-entrypoint-initdb.d/02-shard-03-rs-init.js

log "BOOT" "Waiting for mongos routers..."
wait_for_mongo "mongos-01.femoz.net" 27017
wait_for_mongo "mongos-02.femoz.net" 27017

log "MONGOS" "Adding shards to cluster"
mongosh --host mongos-01.femoz.net --port 27017 --quiet /docker-entrypoint-initdb.d/03-mongos-add-shards.js
log "DB" "Creating collections + validators"
mongosh --host mongos-01.femoz.net --port 27017 --quiet /docker-entrypoint-initdb.d/04-db-collections-validators.js
log "DB" "Creating users"
mongosh --host mongos-01.femoz.net --port 27017 --quiet /docker-entrypoint-initdb.d/05-db-users.js

log "IMPORT" "Importing data into the cluster"
mongoimport \
  --host mongos-01.femoz.net \
  --port 27017 \
  --db video_watch_time \
  --collection viewers \
  --file /docker-entrypoint-initdb.d/viewers.json \
  --jsonArray \
  --stopOnError \
  --verbose

mongoimport \
  --host mongos-01.femoz.net \
  --port 27017 \
  --db video_watch_time \
  --collection devices \
  --file /docker-entrypoint-initdb.d/devices.json \
  --jsonArray \
  --stopOnError \
  --verbose

log "DB" "Reconfiguring collection viewers"
mongosh --host mongos-01.femoz.net --port 27017 --quiet /docker-entrypoint-initdb.d/07-reconfigure-schema-viewer.js
log "DB" "Enabling sharding"
mongosh --host mongos-01.femoz.net --port 27017 --quiet /docker-entrypoint-initdb.d/08-db-enable-sharding.js

log "DONE" "Cluster initialization completed successfully."
