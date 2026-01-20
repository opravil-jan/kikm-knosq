rs.initiate({
  _id: "replicaSet-shard-01",
  members: [
    { _id: 0, host: "shard-01-a.femoz.net:27018", priority: 3 },
    { _id: 1, host: "shard-01-b.femoz.net:27018", priority: 2 },
    { _id: 2, host: "shard-01-c.femoz.net:27018", priority: 1 }
  ]
})