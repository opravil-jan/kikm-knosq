#!/bin/bash


# Pole adresářů ke smazání
DIRECTORIES=(
  "storage/net/femoz/config-server-01/data/configdb"
  "storage/net/femoz/config-server-02/data/configdb"
  "storage/net/femoz/config-server-03/data/configdb"
  "storage/net/femoz/mongos-01/data/db"
  "storage/net/femoz/mongos-02/data/db"
  "storage/net/femoz/shard-01-a/data/db"
  "storage/net/femoz/shard-01-b/data/db"
  "storage/net/femoz/shard-01-c/data/db"
  "storage/net/femoz/shard-02-a/data/db"
  "storage/net/femoz/shard-02-b/data/db"
  "storage/net/femoz/shard-02-c/data/db"
  "storage/net/femoz/shard-03-a/data/db"
  "storage/net/femoz/shard-03-b/data/db"
  "storage/net/femoz/shard-03-c/data/db"
)

wait_for_mongo() {
  local host="$1"
  local port="$2"

  until docker run --rm \
      --network container-network \
      mongo \
      mongosh --host "$host" --port "$port" --quiet --eval 'db.runCommand({ ping: 1 }).ok' \
      2>/dev/null | grep -q '^1$'
  do
    log "---" "Node $host:$port is not responding yet, waiting..."
    sleep 2
  done
}

log() {
  # Usage: log "PREFIX" "message"
  printf '[%s] %s\n' "$1" "$2"
}

# load environment variables from .env file
export $(grep -v '^#' .env | xargs)


docker compose down


if [ "${CLUSTER_INIT_ENABLED:-1}" -eq 1 ]; then

  sudo rm -f ./storage/net/femoz/mongo-keyfile
  openssl rand -base64 756 > ./storage/net/femoz/mongo-keyfile
  sudo chown 999:999 ./storage/net/femoz/mongo-keyfile
  sudo chmod 400 ./storage/net/femoz/mongo-keyfile
  
  if ! docker network inspect "container-network" >/dev/null 2>&1; then
    docker network create "container-network"
  fi
  
  for DIRECTORY in "${DIRECTORIES[@]}"; do
    if [ -d "$DIRECTORY" ]; then
      echo "Deleting directory: $DIRECTORY"
      sudo rm -rf "$DIRECTORY"
    else
      echo "Directory does not exist, skipping: $DIRECTORY"
    fi
    echo "Creating directory: $DIRECTORY"
    mkdir -p "$DIRECTORY"
  done

else 
  echo "SKIP - Cluster already initialized. Exiting."
fi

docker compose up -d

if [ "${CLUSTER_INIT_ENABLED:-1}" -eq 1 ]; then
   
  log "BOOT" "Waiting for config servers..."
  wait_for_mongo "config-server-01.femoz.net" 27019
  wait_for_mongo "config-server-02.femoz.net" 27019
  wait_for_mongo "config-server-03.femoz.net" 27019
  
  log "CONFIG" "Initializing config replica set"
  docker exec -i config-server-01 mongosh --host 127.0.0.1 --port 27019 --quiet < ./funkcni-reseni/01-config-rs-init.js >> /dev/null 2>&1
  
  log "BOOT" "Waiting for shard-01 nodes..."
  wait_for_mongo "shard-01-a.femoz.net" 27018
  wait_for_mongo "shard-01-b.femoz.net" 27018
  wait_for_mongo "shard-01-c.femoz.net" 27018

  log "SHARD-01" "Initializing shard-01 replica set"
  docker exec -i shard-01-a mongosh --host 127.0.0.1 --port 27018 --quiet < ./funkcni-reseni/02-shard-01-rs-init.js >> /dev/null 2>&1
  
  log "BOOT" "Waiting for shard-02 nodes..."
  wait_for_mongo "shard-02-a.femoz.net" 27018
  wait_for_mongo "shard-02-b.femoz.net" 27018
  wait_for_mongo "shard-02-c.femoz.net" 27018

  log "SHARD-02" "Initializing shard-02 replica set"
  docker exec -i shard-02-a mongosh --host 127.0.0.1 --port 27018 --quiet < ./funkcni-reseni/02-shard-02-rs-init.js >> /dev/null 2>&1
  
  log "BOOT" "Waiting for shard-03 nodes..."
  wait_for_mongo "shard-03-a.femoz.net" 27018
  wait_for_mongo "shard-03-b.femoz.net" 27018
  wait_for_mongo "shard-03-c.femoz.net" 27018

  log "SHARD-03" "Initializing shard-03 replica set"
  docker exec -i shard-03-a mongosh --host 127.0.0.1 --port 27018 --quiet < ./funkcni-reseni/02-shard-03-rs-init.js >> /dev/null 2>&1

  log "CONFIG" "Creating cluster admin account"
  docker exec -i config-server-01 mongosh --host 127.0.0.1 --port 27019 --quiet < ./funkcni-reseni/03-create-cluster-admin.js >> /dev/null 2>&1

  log "BOOT" "Waiting for mongos routers..."
  wait_for_mongo "mongos-01.femoz.net" 27017
  wait_for_mongo "mongos-02.femoz.net" 27017

  log "MONGODB" "Adding shards to cluster"
  docker run --rm \
    --network container-network \
    -v "$(pwd)/funkcni-reseni:/scripts:ro" \
    mongo \
    mongosh \
      --host mongos-01.femoz.net \
      --port 27017 \
      --username "${CLUSTER_ADMIN_USERNAME}" \
      --password "${CLUSTER_ADMIN_PASSWORD}" \
      --authenticationDatabase "${CLUSTER_ADMIN_AUTHENTICATION_DATABASE}" \
      --quiet /scripts/04-mongos-add-shards.js

  log "DB" "Creating collections + validators"
  docker run --rm \
    --network container-network \
    -v "$(pwd)/funkcni-reseni:/scripts:ro" \
    mongo \
    mongosh \
      --host mongos-01.femoz.net \
      --port 27017 \
      --username "${CLUSTER_ADMIN_USERNAME}" \
      --password "${CLUSTER_ADMIN_PASSWORD}" \
      --authenticationDatabase "${CLUSTER_ADMIN_AUTHENTICATION_DATABASE}" \
      --quiet /scripts/05-db-collections-validators.js

  log "DB" "Enabling sharding"
  docker run --rm \
    --network container-network \
    -v "$(pwd)/funkcni-reseni:/scripts:ro" \
    mongo \
    mongosh \
      --host mongodb.femoz.net \
      --port 27017 \
      --username "${CLUSTER_ADMIN_USERNAME}" \
      --password "${CLUSTER_ADMIN_PASSWORD}" \
      --authenticationDatabase "${CLUSTER_ADMIN_AUTHENTICATION_DATABASE}" \
      --quiet /scripts/06-db-enable-sharding.js
 
  log "DB" "Creating users"
  docker run --rm \
    --network container-network \
    -v "$(pwd)/funkcni-reseni:/scripts:ro" \
    mongo \
    mongosh \
      --host mongodb.femoz.net \
      --port 27017 \
      --username "${CLUSTER_ADMIN_USERNAME}" \
      --password "${CLUSTER_ADMIN_PASSWORD}" \
      --authenticationDatabase "${CLUSTER_ADMIN_AUTHENTICATION_DATABASE}" \
      --quiet /scripts/07-db-users.js

  log "IMPORT" "Importing data into the cluster"

  docker run --rm \
    --network container-network \
    -v "$(pwd)/data:/data:ro" \
    mongo \
    mongoimport \
      --host mongos-01.femoz.net \
      --port 27017 \
      --username "${VIDEO_WATCH_TIME_USERNAME}" \
      --password "${VIDEO_WATCH_TIME_PASSWORD}" \
      --authenticationDatabase "${VIDEO_WATCH_TIME_AUTHENTICATION_DATABASE}" \
      --db video_watch_time \
      --collection devices \
      --file /data/devices.json \
      --jsonArray \
      --stopOnError \
      --verbose

  docker run --rm \
    --network container-network \
    -v "$(pwd)/data:/data:ro" \
    mongo \
    mongoimport \
      --host mongos-01.femoz.net \
      --port 27017 \
      --username "${VIDEO_WATCH_TIME_USERNAME}" \
      --password "${VIDEO_WATCH_TIME_PASSWORD}" \
      --authenticationDatabase "${VIDEO_WATCH_TIME_AUTHENTICATION_DATABASE}" \
      --db video_watch_time \
      --collection viewers \
      --file /data/viewers.json \
      --jsonArray \
      --stopOnError \
      --verbose

#  sed -i 's/^CLUSTER_INIT_ENABLED=.*/CLUSTER_INIT_ENABLED=0/' .env

  log "DONE" "Cluster initialization completed successfully."

fi
