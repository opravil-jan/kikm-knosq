#!/bin/bash

# load environment variables from .env file
export $(grep -v '^#' .env | xargs)

docker run --rm \
    --network container-network \
    -v "$(pwd)/dotazy:/queries:ro" \
    mongo \
    mongosh \
      --host mongodb.femoz.net \
      --port 27017 \
      --username "${VIDEO_WATCH_TIME_USERNAME}" \
      --password "${VIDEO_WATCH_TIME_PASSWORD}" \
      --authenticationDatabase "${VIDEO_WATCH_TIME_AUTHENTICATION_DATABASE}" \
      --quiet /queries/queries.js