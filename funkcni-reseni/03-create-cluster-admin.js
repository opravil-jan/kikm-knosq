db = db.getSiblingDB("admin");

db.createUser({
  user: "cluster-admin",
  pwd: "gaetaiNgaisou6eilahmoS6chahr3ohf",
  roles: [{ role: "root", db: "admin" }],
});
