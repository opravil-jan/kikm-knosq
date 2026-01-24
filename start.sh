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

# load environment variables from .env file
export $(grep -v '^#' .env | xargs)

docker compose down

if [ "${CLUSTER_INIT_ENABLED:-1}" -eq 1 ]; then

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
#docker container prune
