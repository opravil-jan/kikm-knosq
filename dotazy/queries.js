db = db.getSiblingDB("video_watch_time");
let result;

print("=== Create indexes ===");

db.devices.createIndex({ idec: 1 });

db.viewers.createIndex({ deviceId: 1 });
db.devices.createIndex({ deviceId: 1 });
db.viewers.createIndex(
  { sidp: 1 },
  { partialFilterExpression: { finished: false } },
);
db.viewers.createIndex({ userId: 1, updatedAt: -1 });
db.devices.createIndex(
  { updatedAt: 1 },
  { partialFilterExpression: { finished: false } },
);
db.viewers.createIndex(
  { updatedAt: 1, userId: 1 },
  { partialFilterExpression: { finished: false } },
);

print(
  "=== Seznam 20 nejrozkoukanejsich serialu na ktere se divaji prihlaseni divaci ===",
);

result = db.viewers
  .aggregate([
    {
      $match: {
        finished: false,
      },
    },
    {
      $group: {
        _id: "$sidp",
        idecCount: { $sum: 1 },
      },
    },
    {
      $sort: {
        idecCount: -1,
      },
    },
    {
      $limit: 20,
    },
    {
      $project: {
        _id: 0,
        sidp: "$_id",
        idecCount: 1,
      },
    },
  ])
  .toArray();

printjson(result);

print("=== Počet zařízení na kterých se diváci nepřihlašují ===");

result = db.devices
  .aggregate([
    {
      $lookup: {
        from: "viewers",
        localField: "deviceId",
        foreignField: "deviceId",
        as: "viewerRefs",
      },
    },
    {
      $match: {
        $expr: { $eq: [{ $size: "$viewerRefs" }, 0] },
      },
    },
    {
      $group: {
        _id: null,
        devicesNotUsedByViewers: { $sum: 1 },
      },
    },
    {
      $project: {
        _id: 0,
        devicesNotUsedByViewers: 1,
      },
    },
  ])
  .toArray();

printjson(result);

print("=== Seznam deseti nejsledovanejsich videi anonymních diváků ===");

result = db.devices
  .aggregate([
    {
      $match: {
        idec: { $exists: true, $ne: null },
      },
    },

    {
      $group: {
        _id: "$idec",
        recordsCount: { $sum: 1 },
      },
    },
    {
      $sort: {
        recordsCount: -1,
      },
    },
    {
      $limit: 10,
    },
    {
      $project: {
        _id: 0,
        idec: "$_id",
        recordsCount: 1,
      },
    },
  ])
  .toArray();

printjson(result);

print(
  "=== Počet zařízení na kterých se diváci přihlašují a zároveň na nich koukají jako anonymní ===",
);

result = db.devices
  .aggregate([
    {
      $lookup: {
        from: "viewers",
        localField: "deviceId",
        foreignField: "deviceId",
        as: "viewer",
      },
    },
    {
      $match: {
        viewer: { $ne: [] },
      },
    },
    {
      $group: {
        _id: "$deviceId",
      },
    },
    {
      $count: "uniqueDevicesInBoth",
    },
  ])
  .toArray();

printjson(result);

print(
  "=== Celkový počet videi které sledovaly anonymní diváci a nedokoukali je. To jest updatedAt je starší než jeden měsíc ===",
);

const oneMonthAgo = new Date();
oneMonthAgo.setMonth(oneMonthAgo.getMonth() - 1);

result = db.devices.aggregate([
  {
    $match: {
      finished: false,
      updatedAt: { $lt: oneMonthAgo },
    },
  },
  {
    $count: "totalUndoneVideos",
  },
]);

printjson(result);

print(
  "=== Seznam uživatelů kteří nekoukali na žadné video za poslední rok ===",
);
const oneYearAgo = new Date();
oneYearAgo.setFullYear(oneYearAgo.getFullYear() - 1);

result = db.viewers
  .aggregate([
    {
      $group: {
        _id: "$userId",
        lastUpdatedAt: { $max: "$updatedAt" },
      },
    },
    {
      $match: {
        $or: [
          { lastUpdatedAt: { $lt: oneYearAgo } },
          { lastUpdatedAt: { $exists: false } },
        ],
      },
    },
  ])
  .toArray();

printjson(result);

print(
  "=== Kolik průměrně má přihlášený divák rozkoukaných videii za posledni 3 měsíce  ===",
);

const threeMonthsAgo = new Date();
threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

result = db.viewers
  .aggregate([
    // jen poslední 3 měsíce + rozkoukaná videa
    {
      $match: {
        finished: false,
        updatedAt: { $gte: threeMonthsAgo },
      },
    },

    // počet rozkoukaných videí per user
    {
      $group: {
        _id: "$userId",
        rozkoukanaVidea: { $sum: 1 },
      },
    },

    // průměr přes všechny uživatele
    {
      $group: {
        _id: null,
        prumerRozkoukanychVideiNaUzivatele: {
          $avg: "$rozkoukanaVidea",
        },
        pocetUzivatelu: { $sum: 1 },
      },
    },
  ])
  .toArray();

printjson(result);
