db = db.getSiblingDB("video_watch_time");

db.createCollection("devices", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "Device viewing time",
      required: ["deviceId", "idec", "progress"],
      properties: {
        deviceId: {
          bsonType: "string",
          minimum: 16,
          maximum: 16,
          description: "'deviceId' must be a string and is required",
        },
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
});

db.createCollection("viewers", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "Viewers viewing time",
      required: ["userId", "idec", "progress"],
      properties: {
        userId: {
          bsonType: "binData",
          description: "'userId' must be a binary data and is required",
        },
        deviceId: {
          bsonType: "string",
          minimum: 16,
          maximum: 16,
          description: "'deviceId' must be a string and is required",
        },
        deviceId: {
          bsonType: "string",
          minimum: 16,
          maximum: 16,
          description: "'deviceId' must be a string and is required",
        },
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
});
