#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
FX option vols from Bloomberg via xbbg 

- ATM:   {PAIR}V{TENOR} {QUAL} Curncy
- RR/BF: {PAIR}{DELTA}{R|B}{TENOR} {QUAL} Curncy     (legacy tickers from OVDV RR/BF tab)

Reconstruct wing vols (C/P at 10D and 25D) from ATM + RR + BF:
    CallVol = ATM + BF + RR/2
    PutVol  = ATM + BF - RR/2

Also pulls TRADING_DAY_END_TIME_EOD for documentation of the EOD snapshot time.
"""

from xbbg import blp
import pandas as pd
import re
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
OUTDIR = SCRIPT_DIR / "csv_vols"
OUTDIR.mkdir(parents=True, exist_ok=True)

print("SCRIPT:", Path(__file__).resolve())
print("Saving VOL CSV files to:", OUTDIR)

# ---------------------- Config ----------------------
pair_sets = {
    "EURGBP": ["EURUSD", "GBPUSD", "EURGBP"],
    "EURJPY": ["EURUSD", "USDJPY", "EURJPY"],
    "EURCHF": ["EURUSD", "USDCHF", "EURCHF"],
    "EURAUD": ["EURUSD", "AUDUSD", "EURAUD"],
    "EURCAD": ["EURUSD", "USDCAD", "EURCAD"],
    "EURNZD": ["EURUSD", "NZDUSD", "EURNZD"],
    "GBPJPY": ["GBPUSD", "USDJPY", "GBPJPY"],
    "GBPCHF": ["GBPUSD", "USDCHF", "GBPCHF"],
    "GBPAUD": ["GBPUSD", "AUDUSD", "GBPAUD"],
    "GBPCAD": ["GBPUSD", "USDCAD", "GBPCAD"],
    "AUDJPY": ["AUDUSD", "USDJPY", "AUDJPY"],
    "NZDJPY": ["NZDUSD", "USDJPY", "NZDJPY"],
    "CADJPY": ["USDCAD", "USDJPY", "CADJPY"],
    "AUDNZD": ["AUDUSD", "NZDUSD", "AUDNZD"],
}

# Universe = all unique pairs appearing anywhere
pairs = sorted({p for tri in pair_sets.values() for p in tri})

tenors = ["1M", "3M", "6M", "1Y"]   
deltas = ["10", "25"]
start  = "2008-07-01"
end    = "2025-06-30"

# Choose one pricing source and use it everywhere for consistency
QUAL = "BGN"   # "CMPN", "CMPL", "CMPT" are alternatives

print("QUAL:", QUAL)
print("Number of pairs:", len(pairs))
print("Pairs:", pairs)

# Measures to keep as “inputs” to the smile
keep_measures = ["ATM", "RR10", "RR25", "BF10", "BF25"]

# ------------------ Ticker builders -----------------
def ticker_atm(pair: str, tenor: str) -> str:
    # e.g. EURUSDV1M BGN Curncy
    return f"{pair}V{tenor} {QUAL} Curncy"

def ticker_rrbf_legacy(pair: str, tenor: str, delta: str, rb: str) -> str:
    """
    Legacy RR/BF tickers (OVDV RR/BF tab):
      RR:  EURUSD25R1M BGN Curncy
      BF:  EURUSD25B1M BGN Curncy
    """
    return f"{pair}{delta}{rb}{tenor} {QUAL} Curncy"

# ------------------ Parse tickers into (pair, tenor, measure) -----------------
pat_atm = re.compile(r"^([A-Z]{6})V([0-9]+[WMY])\s+(BGN|CMPN|CMPL|CMPT)\s+Curncy$")
pat_leg = re.compile(r"^([A-Z]{6})(10|25)(R|B)([0-9]+[WMY])\s+(BGN|CMPN|CMPL|CMPT)\s+Curncy$")

def parse_sec(sec: str):
    m = pat_atm.match(sec)
    if m:
        return m.group(1), m.group(2), "ATM"

    m = pat_leg.match(sec)
    if m:
        pair, delta, rb, tenor = m.group(1), m.group(2), m.group(3), m.group(4)
        measure = f"RR{delta}" if rb == "R" else f"BF{delta}"
        return pair, tenor, measure

    return None

# ------------------ Build request list -----------------
tickers = []
for p in pairs:
    for t in tenors:
        tickers.append(ticker_atm(p, t))
        for d in deltas:
            tickers.append(ticker_rrbf_legacy(p, t, d, "R"))  # RR
            tickers.append(ticker_rrbf_legacy(p, t, d, "B"))  # BF

tickers = sorted(set(tickers))
print("Total tickers requested:", len(tickers))

# ------------------ Meta fields: EOD snap time -----------------
meta_fields = ["TRADING_DAY_END_TIME_EOD"]
try:
    meta = blp.bdp(tickers, meta_fields)
    meta_path = OUTDIR / "bbg_eod_times_fxvol.csv"
    meta.to_csv(meta_path)
    print("Saved:", meta_path)
except Exception as e:
    print("WARNING: bdp meta pull failed (field/entitlement availability).")
    print("Error:", e)

# ------------------ Download time series -----------------
df = blp.bdh(tickers, "PX_LAST", start_date=start, end_date=end)

if df is None or df.empty:
    raise RuntimeError("BDH returned empty DataFrame for the full ticker list.")

# Flatten columns to security strings
if isinstance(df.columns, pd.MultiIndex):
    df.columns = df.columns.get_level_values(0)

print("Rows:", df.shape[0], "| Date range:", df.index.min(), "to", df.index.max())
na_rate = df.isna().mean().sort_values(ascending=False)
print("\nWorst tickers by NaN % (top 15):")
print(na_rate.head(15))

# ------------------ Keep and reshape to MultiIndex -----------------
parsed = [parse_sec(s) for s in df.columns]
keep_mask = [p is not None for p in parsed]

dropped = [c for c, ok in zip(df.columns, keep_mask) if not ok]
if dropped:
    print("\nDropping unrecognized columns (showing up to 20):")
    for d in dropped[:20]:
        print("  ", d)

df = df.loc[:, keep_mask]
parsed = [p for p in parsed if p is not None]

df.columns = pd.MultiIndex.from_tuples(parsed, names=["pair", "tenor", "measure"])
df = df.groupby(axis=1, level=["pair", "tenor", "measure"]).first().sort_index(axis=1)

# Keep the core smile inputs
df = df.loc[:, df.columns.get_level_values("measure").isin(keep_measures)]
print("\nParsed panel head:")
print(df.head())

# ------------------ Reconstruct wing vols -----------------
# CallVol = ATM + BF + RR/2
# PutVol  = ATM + BF - RR/2
def reconstruct_wings(panel: pd.DataFrame) -> pd.DataFrame:
    out = panel.copy()
    idx = out.index

    tuples = list(out.columns)
    pairs_ = sorted(set([t[0] for t in tuples]))
    tenors_ = sorted(set([t[1] for t in tuples]))

    new_cols = {}
    for p in pairs_:
        for t in tenors_:
            if (p, t, "ATM") not in out.columns:
                continue
            atm = out[(p, t, "ATM")]

            for d in ["10", "25"]:
                rr_key = f"RR{d}"
                bf_key = f"BF{d}"
                if (p, t, rr_key) in out.columns and (p, t, bf_key) in out.columns:
                    rr = out[(p, t, rr_key)]
                    bf = out[(p, t, bf_key)]
                    new_cols[(p, t, f"C{d}")] = atm + bf + 0.5 * rr
                    new_cols[(p, t, f"P{d}")] = atm + bf - 0.5 * rr

    if new_cols:
        add = pd.DataFrame(new_cols, index=idx)
        add.columns = pd.MultiIndex.from_tuples(add.columns, names=["pair", "tenor", "measure"])
        out = pd.concat([out, add], axis=1).sort_index(axis=1)

    return out

df = reconstruct_wings(df)

# ------------------ Save per pair -----------------
saved = 0
skipped = 0

for p in pairs:
    if p not in df.columns.get_level_values("pair"):
        print(f"\n[WARN] No data for {p} found. Skipping export.")
        skipped += 1
        continue

    out = df[p].copy()  # columns: (tenor, measure)

    # Single-level headers: t1M_ATM, t1M_RR25, t1M_BF25, t1M_C25, t1M_P25, ...
    out.columns = [f"t{tenor}_{measure}" for (tenor, measure) in out.columns.to_list()]

    # Add explicit date column so that MATLAB can read it easier  later
    out = out.reset_index().rename(columns={out.index.name or "index": "date"})

    # Filename convention:
    out_path = OUTDIR / f"fxvol_{p}.csv"


    out.to_csv(out_path, index=False, float_format="%.6f")
    print(f"Saved: {out_path} | cols={out.shape[1]} | example={list(out.columns)[:10]}")
    saved += 1

print(f"\nDONE. Saved {saved} VOL CSVs into {OUTDIR}, skipped {skipped}.")



