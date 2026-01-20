db = db.getSiblingDB('video_watch_time') 
sh.enableSharding("video_watch_time");
db.devices.createIndex({ deviceId: "hashed" })
sh.shardCollection("video_watch_time.devices", { deviceId: "hashed" });
db.viewers.createIndex({ userId: "hashed" })
sh.shardCollection("video_watch_time.viewers", { userId: "hashed" });
