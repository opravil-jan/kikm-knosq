db = db.getSiblingDB("video_watch_time");
db.createUser({
  user: "pcm",
  pwd: "woo4rae9Iepopeithoor1quieYo6Yai0",
  roles: [{ role: "readWrite", db: "video_watch_time" }],
});

db = db.getSiblingDB("admin");

db.createUser({
  user: "cluster-admin",
  pwd: "gaetaiNgaisou6eilahmoS6chahr3ohf",
  roles: [{ role: "root", db: "admin" }],
});

db = db.getSiblingDB("video_watch_time");
