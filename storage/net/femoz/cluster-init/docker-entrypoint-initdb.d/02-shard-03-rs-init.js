rs.initiate({
  _id: "replicaSet-shard-03",
  members: [
    { _id: 0, host: "shard-03-a.femoz.net:27018", priority: 3 },
    { _id: 1, host: "shard-03-b.femoz.net:27018", priority: 2 },
    { _id: 2, host: "shard-03-c.femoz.net:27018", priority: 1 }
  ]
})