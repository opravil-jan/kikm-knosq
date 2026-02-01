#!/usr/bin/env python3
import os
import math
import argparse
from dataclasses import dataclass, field
from typing import Any, Dict, Iterable, Optional, TextIO

import numpy as np
import pandas as pd
import ijson
import matplotlib.pyplot as plt


# -----------------------------
# KONFIGURACE
# -----------------------------
DEFAULT_FILES = {
    "devices": "devices.json",
    "viewers": "viewers.json",
}

SCHEMA_FIELDS = {
    "devices": ["deviceId", "sidp", "idec", "progress", "finished", "updatedAt"],
    "viewers": ["userId", "deviceId", "sidp", "idec", "progress", "finished", "updatedAt"],
}

UNIQUE_FIELDS = ["sidp", "idec", "userId", "deviceId"]


# -----------------------------
# STREAMING JSON
# -----------------------------
def stream_json_array(path: str) -> Iterable[Dict[str, Any]]:
    with open(path, "rb") as f:
        for doc in ijson.items(f, "item"):
            if isinstance(doc, dict):
                yield doc


def is_missing_value(v: Any) -> bool:
    if v is None:
        return True
    if isinstance(v, str) and v.strip() == "":
        return True
    return False


def normalize_updated_at(updated_at: Any) -> Any:
    if updated_at is None:
        return None

    if isinstance(updated_at, dict):
        if "$date" in updated_at:
            return updated_at.get("$date")
        for k in ("date", "value", "timestamp", "time"):
            if k in updated_at:
                return updated_at.get(k)
        return None

    return updated_at


def coerce_month(updated_at: Any) -> Optional[pd.Period]:
    ua = normalize_updated_at(updated_at)
    if ua is None:
        return None

    if isinstance(ua, (int, np.integer, float, np.floating)):
        try:
            ts = float(ua)
            if ts > 1e12:  # ms
                dt = pd.to_datetime(int(ts), unit="ms", utc=True, errors="coerce")
            else:          # s
                dt = pd.to_datetime(ts, unit="s", utc=True, errors="coerce")
        except Exception:
            return None
    else:
        try:
            dt = pd.to_datetime(ua, utc=True, errors="coerce")
        except Exception:
            return None

    if pd.isna(dt):
        return None

    dt = dt.tz_localize(None)
    return dt.to_period("M")


def coerce_bool(v: Any) -> Optional[bool]:
    if v is None:
        return None
    if isinstance(v, bool):
        return v
    if isinstance(v, (int, np.integer)):
        if v == 0:
            return False
        if v == 1:
            return True
        return None
    if isinstance(v, str):
        s = v.strip().lower()
        if s in {"true", "t", "yes", "y", "1"}:
            return True
        if s in {"false", "f", "no", "n", "0"}:
            return False
    return None


def coerce_float(v: Any) -> Optional[float]:
    if v is None:
        return None
    if isinstance(v, (int, float, np.integer, np.floating)):
        if isinstance(v, float) and (math.isnan(v) or math.isinf(v)):
            return None
        return float(v)
    if isinstance(v, str):
        s = v.strip().replace(",", ".")
        if s == "":
            return None
        try:
            x = float(s)
            if math.isnan(x) or math.isinf(x):
                return None
            return x
        except ValueError:
            return None
    return None


# -----------------------------
# MĚSÍČNÍ AGREGACE
# -----------------------------
@dataclass
class MonthlyAgg:
    # původní metriky necháváme, ale graf už je nepoužije
    records: int = 0
    sum_progress: float = 0.0
    progress_count: int = 0
    finished_true: int = 0
    finished_false: int = 0
    finished_missing: int = 0

    # NOVĚ: počet idec v měsíci = počet sledovaných videí v měsíci (součet záznamů s idec)
    idec_count: int = 0

    def add(self, progress: Optional[float], finished: Optional[bool], idec_present: bool) -> None:
        self.records += 1

        if progress is not None:
            self.sum_progress += progress
            self.progress_count += 1

        if finished is True:
            self.finished_true += 1
        elif finished is False:
            self.finished_false += 1
        else:
            self.finished_missing += 1

        # počítáme idec jako "počet sledování" => každý záznam s idec přidá 1
        if idec_present:
            self.idec_count += 1


@dataclass
class DatasetStats:
    name: str
    total: int = 0
    missing: Dict[str, int] = field(default_factory=dict)
    finished_true: int = 0
    finished_false: int = 0
    finished_missing: int = 0
    monthly: Dict[pd.Period, MonthlyAgg] = field(default_factory=dict)
    uniques: Dict[str, set] = field(default_factory=lambda: {f: set() for f in UNIQUE_FIELDS})

    def ensure_fields(self, fields):
        for f in fields:
            self.missing.setdefault(f, 0)

    def add_doc(self, doc: Dict[str, Any], fields: list):
        self.total += 1

        for f in fields:
            if f not in doc or is_missing_value(doc.get(f)):
                self.missing[f] += 1

        for uf in UNIQUE_FIELDS:
            if uf in doc and not is_missing_value(doc.get(uf)):
                self.uniques[uf].add(str(doc.get(uf)))

        fin = coerce_bool(doc.get("finished"))
        if fin is True:
            self.finished_true += 1
        elif fin is False:
            self.finished_false += 1
        else:
            self.finished_missing += 1

        month = coerce_month(doc.get("updatedAt"))
        if month is not None:
            prog = coerce_float(doc.get("progress"))

            # idec nijak neupravujeme – jen ověříme, že existuje a není prázdné
            idec_present = ("idec" in doc) and (not is_missing_value(doc.get("idec")))

            agg = self.monthly.get(month)
            if agg is None:
                agg = MonthlyAgg()
                self.monthly[month] = agg

            agg.add(prog, fin, idec_present)


def analyze_dataset(name: str, path: str) -> DatasetStats:
    fields = SCHEMA_FIELDS[name]
    stats = DatasetStats(name=name)
    stats.ensure_fields(fields)

    for doc in stream_json_array(path):
        stats.add_doc(doc, fields)

    return stats


def monthly_df(stats: DatasetStats) -> pd.DataFrame:
    """
    Vrací DataFrame jen s tím, co potřebujeme pro graf:
    - month
    - idec_count (součet všech záznamů s idec v měsíci)
    """
    rows = []
    for month, agg in stats.monthly.items():
        rows.append({
            "month": str(month),
            "idec_count": agg.idec_count,
        })

    df = pd.DataFrame(rows)
    if not df.empty:
        df["month"] = pd.PeriodIndex(df["month"], freq="M")
        df = df.sort_values("month")
        df["month"] = df["month"].astype(str)
    return df


def plot_monthly(df: pd.DataFrame, title: str, out_png: str) -> None:
    """
    Graf obsahuje pouze:
    - počet idec v daném měsíci (součet záznamů s idec)
    """
    if df.empty:
        print(f"[WARN] {title}: nejsou data pro měsíční graf (updatedAt chybí / neparsovatelné).")
        return

    x = df["month"].tolist()
    y = df["idec_count"].to_numpy()

    plt.figure()
    plt.plot(x, y, marker="o", label="Počet sledovaných videí (počet idec)")
    plt.title(title)
    plt.xlabel("Měsíc (updatedAt)")
    plt.ylabel("Počet sledovaných videí")
    plt.xticks(rotation=45, ha="right")
    plt.legend()
    plt.tight_layout()
    plt.savefig(out_png, dpi=150)
    plt.close()


def _write(line: str, fp: Optional[TextIO] = None) -> None:
    print(line)
    if fp is not None:
        fp.write(line + "\n")


def print_summary(stats: DatasetStats, fp: Optional[TextIO] = None) -> None:
    _write(f"\n===== {stats.name.upper()} =====", fp)
    _write(f"Počet záznamů: {stats.total:,}", fp)

    _write("\nPrázdná pole (missing/null/\"\"):", fp)
    for k, v in sorted(stats.missing.items(), key=lambda kv: kv[1], reverse=True):
        pct = (v / stats.total * 100) if stats.total else 0
        _write(f"- {k:<12} {v:>10,}  ({pct:>6.2f} %)", fp)

    _write("\nfinished (true/false/missing):", fp)
    _write(f"- true:    {stats.finished_true:,}", fp)
    _write(f"- false:   {stats.finished_false:,}", fp)
    _write(f"- missing: {stats.finished_missing:,}", fp)

    _write("\nUnikátní hodnoty:", fp)
    for f in UNIQUE_FIELDS:
        _write(f"- {f:<8} {len(stats.uniques[f]):,}", fp)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data-dir", default="./data", help="Adresář se vstupními JSON soubory")
    ap.add_argument("--out-dir", default="./report", help="Adresář pro výstupy (CSV/PNG/TXT)")
    ap.add_argument("--datasets", nargs="*", default=["devices", "viewers"],
                    help="Které datasety analyzovat: devices viewers")
    args = ap.parse_args()

    data_dir = args.data_dir
    out_dir = args.out_dir

    os.makedirs(out_dir, exist_ok=True)

    files = {k: os.path.join(data_dir, v) for k, v in DEFAULT_FILES.items()}

    summary_path = os.path.join(out_dir, "summary.txt")
    with open(summary_path, "w", encoding="utf-8") as summary_fp:
        _write(f"Report directory: {os.path.abspath(out_dir)}", summary_fp)
        _write(f"Data directory:   {os.path.abspath(data_dir)}", summary_fp)

        for name in args.datasets:
            if name not in files:
                _write(f"\n[WARN] Neznámý dataset: {name}", summary_fp)
                continue

            path = files[name]
            if not os.path.exists(path):
                _write(f"\n[WARN] Soubor nenalezen: {path}", summary_fp)
                continue

            stats = analyze_dataset(name, path)
            print_summary(stats, summary_fp)

            df = monthly_df(stats)

            # CSV je teď jen month + idec_count
            csv_out = os.path.join(out_dir, f"{name}_monthly.csv")
            png_out = os.path.join(out_dir, f"{name}_monthly_idec_count.png")

            if not df.empty:
                df.to_csv(csv_out, index=False, encoding="utf-8")
                _write(f"\nMěsíční přehled (počet idec) uložen do: {csv_out}", summary_fp)
                _write(df.head(24).to_string(index=False), summary_fp)
            else:
                _write("\nMěsíční přehled: žádná data (updatedAt chybí / neparsovatelné).", summary_fp)

            plot_monthly(
                df,
                title=f"{name}: počet sledovaných videí za měsíc (počet idec)",
                out_png=png_out
            )
            if os.path.exists(png_out):
                _write(f"Graf uložen do: {png_out}", summary_fp)

    print(f"\nHotovo. Všechny výstupy najdeš v: {os.path.abspath(out_dir)}")
    print(f"- souhrn: {os.path.abspath(summary_path)}")


if __name__ == "__main__":
    main()
