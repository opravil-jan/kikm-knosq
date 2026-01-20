db = db.getSiblingDB('video_watch_time') 

db.runCommand({
  collMod: "viewers",
  validationLevel: "off"
});

db.viewers.updateMany(
  {
    userId_temporary: { $type: "string" }
  },
  [
    {
      $set: {
        userId: { $toUUID: "$userId_temporary" }
      }
    },
    {
      $unset: "userId_temporary"
    }
  ]
);

db.runCommand({
  collMod: "viewers",
   validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "Viewers viewing time",
      required: ["userId", "idec", "progress"],
      properties: {
        userId: {
          bsonType: "binData",
          description: "'userId' must be a binary data and is required",},
        sidp: {
          bsonType: "long",
          minimum: 10000,
          maximum: 20000000000,
          description:
            "'sidp' must be an integer in range 10000 to 20000000000 and is required",
        },
        idec: {
          bsonType: "string",
          minLength: 3,
          maxLength: 20,
        },
        progress: {
          bsonType: "int",
          minimum: 0,
          maximum: 172800,
          description: "'progress' shows last video watch time time in second",
        },
        finished: {
          bsonType: "bool",
          description: "'finished' tells if viewer seen whole movie",
        },
        createdAt: { bsonType: "date" },
        updatedAt: { bsonType: "date" },
      },
    },
  },
  validationLevel: "strict",
  validationAction: "error"
});
