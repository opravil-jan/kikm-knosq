rs.initiate({
  _id: 'replicaSet-config',
  configsvr: true,
  members: [
    { _id: 0, host: 'config-server-01.femoz.net:27019', priority: 3 },
    { _id: 1, host: 'config-server-02.femoz.net:27019', priority: 2 },
    { _id: 2, host: 'config-server-03.femoz.net:27019', priority: 1 }
  ]
})
