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

docker compose down

for DIRECTORY in "${DIRECTORIES[@]}"; do
  if [ -d "$DIRECTORY" ]; then
    echo "Mažu adresář: $DIRECTORY"
    sudo rm -rf "$DIRECTORY"
  else
    echo "Adresář neexistuje, přeskakuji: $DIRECTORY"
  fi
  mkdir -p "$DIRECTORY"
done

docker compose up -d
#docker container prune
