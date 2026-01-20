rs.initiate({
  _id: "replicaSet-shard-02",
  members: [
    { _id: 0, host: "shard-02-a.femoz.net:27018", priority: 3 },
    { _id: 1, host: "shard-02-b.femoz.net:27018", priority: 2 },
    { _id: 2, host: "shard-02-c.femoz.net:27018", priority: 1 }
  ]
})