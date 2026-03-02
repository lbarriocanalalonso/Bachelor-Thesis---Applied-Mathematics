#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Created on Thu Feb  5 09:38:22 2026

@author: de-vriestjeerd
"""

#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
FX option vols from Bloomberg via xbbg (Recommendation A):

- ATM:   {PAIR}V{TENOR} {QUAL} Curncy
- RR/BF: {PAIR}{DELTA}{R|B}{TENOR} {QUAL} Curncy     (legacy tickers)

Reconstruct wing vols (C/P at 10D and 25D) from ATM + RR + BF:
    CallVol = ATM + BF + RR/2
    PutVol  = ATM + BF - RR/2

Also pulls TRADING_DAY_END_TIME_EOD for documentation of the EOD snapshot time.
"""

from xbbg import blp
import pandas as pd
import numpy as np
import re

# ---------------------- Config ----------------------
pairs   = ['EURUSD', 'GBPUSD', 'EURGBP']
tenors  = ['1M', '3M', '6M', '1Y']
deltas  = ['10', '25']
start   = '2008-07-01'
end     = '2025-06-30'

# Choose ONE pricing source / close convention and use it everywhere
QUAL = "BGN"   # alternatives: "CMPN" (NY composite), "CMPL" (London composite), "CMPT" (Tokyo composite)

# ------------------ Ticker builders -----------------
def ticker_atm(pair: str, tenor: str) -> str:
    # e.g. EURUSDV1M BGN Curncy
    return f'{pair}V{tenor} {QUAL} Curncy'

def ticker_rrbf_legacy(pair: str, tenor: str, delta: str, rb: str) -> str:
    """
    Legacy RR/BF tickers (from OVDV RR/BF tab):
      RR:  EURUSD25R1M BGN Curncy
      BF:  EURUSD25B1M BGN Curncy
    """
    return f'{pair}{delta}{rb}{tenor} {QUAL} Curncy'

# ------------------ Build request list -----------------
tickers = []
for p in pairs:
    for t in tenors:
        tickers.append(ticker_atm(p, t))
        for d in deltas:
            tickers.append(ticker_rrbf_legacy(p, t, d, 'R'))  # RR
            tickers.append(ticker_rrbf_legacy(p, t, d, 'B'))  # BF

tickers = sorted(set(tickers))

# ------------------ Meta fields (EOD snap time) -----------------
# (Optional but recommended for documentation)
meta_fields = ["TRADING_DAY_END_TIME_EOD"]
try:
    meta = blp.bdp(tickers, meta_fields)
    meta.to_csv("bbg_eod_times_fxvol.csv")
    print("Saved meta field TRADING_DAY_END_TIME_EOD to bbg_eod_times_fxvol.csv")
except Exception as e:
    print("WARNING: bdp meta pull failed (often due to entitlement/field availability).")
    print("Error:", e)

# ------------------ Download time series -----------------
df = blp.bdh(tickers, 'PX_LAST', start_date=start, end_date=end)

# Flatten columns to security strings
if isinstance(df.columns, pd.MultiIndex):
    df.columns = df.columns.get_level_values(0)

print("Rows:", df.shape[0], "| Date range:", df.index.min(), "to", df.index.max())
na_rate = df.isna().mean().sort_values(ascending=False)
print("\nWorst tickers by NaN % (top 15):")
print(na_rate.head(15))

# ------------------ Parse tickers into (pair, tenor, measure) -----------------
# ATM: EURUSDV1M BGN Curncy   (QUAL can be BGN/CMPN/CMPL/CMPT)
pat_atm = re.compile(r'^([A-Z]{6})V([0-9]+[WMY])\s+(BGN|CMPN|CMPL|CMPT)\s+Curncy$')

# Legacy RR/BF: EURUSD25R1M BGN Curncy, EURUSD10B3M CMPL Curncy
pat_leg = re.compile(r'^([A-Z]{6})(10|25)(R|B)([0-9]+[WMY])\s+(BGN|CMPN|CMPL|CMPT)\s+Curncy$')

def parse_sec(sec: str):
    m = pat_atm.match(sec)
    if m:
        pair, tenor = m.group(1), m.group(2)
        return pair, tenor, 'ATM'

    m = pat_leg.match(sec)
    if m:
        pair, delta, rb, tenor = m.group(1), m.group(2), m.group(3), m.group(4)
        if rb == 'R':
            measure = f'RR{delta}'
        else:
            measure = f'BF{delta}'
        return pair, tenor, measure

    return None

parsed = [parse_sec(s) for s in df.columns]
keep_mask = [p is not None for p in parsed]

if not all(keep_mask):
    dropped = [c for c, ok in zip(df.columns, keep_mask) if not ok]
    print("\nDropping unrecognized columns (showing up to 20):")
    for d in dropped[:20]:
        print("  ", d)

df = df.loc[:, keep_mask]
parsed = [p for p in parsed if p is not None]

df.columns = pd.MultiIndex.from_tuples(parsed, names=['pair', 'tenor', 'measure'])
df = df.groupby(axis=1, level=['pair', 'tenor', 'measure']).first().sort_index(axis=1)

# Keep the core smile inputs
keep_measures = ['ATM', 'RR10', 'RR25', 'BF10', 'BF25']
df = df.loc[:, df.columns.get_level_values('measure').isin(keep_measures)]

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
            try:
                atm  = out[(p, t, 'ATM')]
            except KeyError:
                continue

            for d in ['10', '25']:
                rr_key = f'RR{d}'
                bf_key = f'BF{d}'
                if (p, t, rr_key) in out.columns and (p, t, bf_key) in out.columns:
                    rr = out[(p, t, rr_key)]
                    bf = out[(p, t, bf_key)]
                    call = atm + bf + 0.5 * rr
                    put  = atm + bf - 0.5 * rr
                    new_cols[(p, t, f'C{d}')] = call
                    new_cols[(p, t, f'P{d}')] = put

    if new_cols:
        add = pd.DataFrame(new_cols, index=idx)
        add.columns = pd.MultiIndex.from_tuples(add.columns, names=['pair','tenor','measure'])
        out = pd.concat([out, add], axis=1).sort_index(axis=1)

    return out

df = reconstruct_wings(df)

# ------------------ Save per pair (single-level headers) -----------------
for p in pairs:
    if p not in df.columns.get_level_values('pair'):
        print(f"\nNo data for {p} found in parsed DataFrame. Skipping export.")
        continue

    out = df[p].copy()  # columns: (tenor, measure)
    # Flatten header: t1M_ATM, t1M_RR25, t1M_BF25, t1M_C25, t1M_P25, ...
    out.columns = [f"t{tenor}_{measure}" for tenor, measure in out.columns]
    out.to_csv(f'fxvol_{p}_{QUAL}.csv', float_format='%.6f')
    print(f"\nSaved fxvol_{p}_{QUAL}.csv with {out.shape[1]} columns. Example cols: {list(out.columns)[:12]}")
