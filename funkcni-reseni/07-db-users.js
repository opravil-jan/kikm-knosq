db = db.getSiblingDB("video_watch_time");
db.createUser({
  user: "pcm",
  pwd: "woo4rae9Iepopeithoor1quieYo6Yai0",
  roles: [{ role: "readWrite", db: "video_watch_time" }],
});
