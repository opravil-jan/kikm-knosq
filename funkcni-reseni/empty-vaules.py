import os
import ijson

DATA_DIR = "./storage/net/femoz/cluster-init/docker-entrypoint-initdb.d/data"

FILES = {
    "devices": os.path.join(DATA_DIR, "devices.json"),
    "viewers": os.path.join(DATA_DIR, "viewers.json"),
}

SCHEMA_FIELDS = {
    "devices": ["deviceId", "sidp", "idec", "progress", "finished", "createdAt", "updatedAt"],
    "viewers": ["userId", "deviceId", "sidp", "idec", "progress", "finished", "createdAt", "updatedAt"],
}

def is_missing(doc: dict, field: str) -> bool:
    # prázdné = chybějící klíč nebo explicitně null
    return field not in doc or doc[field] is None

def analyze_json_array(name: str, path: str):
    fields = SCHEMA_FIELDS[name]
    missing = {f: 0 for f in fields}
    total = 0

    with open(path, "rb") as f:
        # předpoklad: soubor je JSON array: [ {...}, {...}, ... ]
        for doc in ijson.items(f, "item"):
            total += 1
            for field in fields:
                if is_missing(doc, field):
                    missing[field] += 1

    print(f"\n===== {name} =====")
    print(f"Počet záznamů: {total:,}")
    print("\nPočet prázdných hodnot pro jednotlivá pole:")
    for k, v in sorted(missing.items(), key=lambda kv: kv[1], reverse=True):
        print(f"{k:<10} {v}")

def main():
    for name, path in FILES.items():
        if not os.path.exists(path):
            print(f"Soubor nenalezen: {path}")
            continue
        analyze_json_array(name, path)

if __name__ == "__main__":
    main()
