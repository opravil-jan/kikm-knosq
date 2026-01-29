docker run --rm -it \
  --network container-network \
  -v "$PWD/dotazy/queries.js:/opt/queries.js:ro" \
  mongo mongosh "mongodb://haproxy.femoz.net:27017/video_watch_time" /opt/queries.js