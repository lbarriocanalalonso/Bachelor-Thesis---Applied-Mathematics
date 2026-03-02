# --- FX: Excel with 1M/3M rates + CIP forwards + documented EOD snap time (TRADING_DAY_END_TIME_EOD)

from __future__ import annotations

from typing import Dict, List, Tuple
import pandas as pd
from xbbg import blp

# ---------------- Config ----------------
#use benchmark tickers only

start, end = "2008-07-01", "2022-12-31"
out_xlsx = "fx_inputs_1m_3m_ALL_PAIRS_LIBOR_ONLY_upto2022.xlsx"

# Choose ONE close convention everywhere (as per Bloomberg helpdesk)
QUAL = "BGN"   # or "CMPN" (NY), "CMPL" (London), "CMPT" (Tokyo)

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

tenors = ["1M", "3M"]
tau = {"1M": 1 / 12, "3M": 3 / 12}

# ---------------- Comparable benchmark candidates ----------------
# Each entry is a list of *IBOR-style* tickers (without the trailing ' Index') that are intended to be comparable
# across currencies (term unsecured bank funding benchmarks, or the closest standard local equivalent).
#
# We also auto-generate fallback variants by adding prefixes 'V' and 'F' (Bloomberg/ISDA conventions differ by series),
# and we prefer those if available to preserve continuity post-cessation.
BASE_IBOR_TICKERS: Dict[Tuple[str, str], List[str]] = {
    # EURIBOR
    ("EUR", "1M"): ["EUR001M"],
    ("EUR", "3M"): ["EUR003M"],

    # USD LIBOR
    ("USD", "1M"): ["US0001M"],
    ("USD", "3M"): ["US0003M"],

    # GBP LIBOR
    ("GBP", "1M"): ["BP0001M"],
    ("GBP", "3M"): ["BP0003M"],

    # JPY LIBOR
    ("JPY", "1M"): ["JY0001M"],
    ("JPY", "3M"): ["JY0003M"],

    # CHF LIBOR
    ("CHF", "1M"): ["SF0001M"],
    ("CHF", "3M"): ["SF0003M"],

    # AUD BBSW
    ("AUD", "1M"): ["BBSW1M"],
    ("AUD", "3M"): ["BBSW3M"],

    # CAD CDOR (some environments use CDOR3 instead of CDOR03)
    ("CAD", "1M"): ["CDOR01", "CDOR1"],
    ("CAD", "3M"): ["CDOR03", "CDOR3"],

    # NZD BKBM BID series on Bloomberg uses NFIX*BID tickers
    ("NZD", "1M"): ["NFIX1BID"],
    ("NZD", "3M"): ["NFIX3BID"],
}

# Optional hard overrides if your Bloomberg has a special ticker for one currency/tenor
EXTRA_TICKERS: Dict[Tuple[str, str], List[str]] = {
    # Example:
    # ("EUR", "1M"): ["EUR001M"],
}

# ---------------- Helpers ----------------
def unique_preserve_order(items: List[str]) -> List[str]:
    seen = set()
    out = []
    for x in items:
        if x not in seen:
            seen.add(x)
            out.append(x)
    return out

def currencies_from_pairs(pairs: List[str]) -> List[str]:
    ccys = set()
    for p in pairs:
        p = p.strip().upper()
        if len(p) == 6:
            ccys.add(p[:3])
            ccys.add(p[3:])
    return sorted(ccys)

def flatten_cols(df: pd.DataFrame) -> pd.DataFrame:
    if isinstance(df.columns, pd.MultiIndex):
        df.columns = df.columns.get_level_values(0)
    return df

def df_simple(rate: pd.Series, T: float) -> pd.Series:
    return 1.0 / (1.0 + rate * T)

def build_rate_candidates(ccy: str, tenor: str) -> List[str]:
    """Return candidate Bloomberg tickers (with trailing ' Index') for (ccy, tenor).

    IMPORTANT (per user request): we only use *plain* benchmark tickers here.
    That means: no fallback variants (no V* or F* prefixes). We still allow multiple
    plain candidates when Bloomberg has more than one common screen ticker
    (e.g., CAD CDOR01 vs CDOR1).
    """
    ccy = ccy.upper()
    tenor = tenor.upper()

    base_list = EXTRA_TICKERS.get((ccy, tenor), BASE_IBOR_TICKERS.get((ccy, tenor), []))
    if not base_list:
        return []

    out = [f"{base} Index" for base in base_list]

    # De-duplicate while preserving order
    return unique_preserve_order(out)

def choose_best_coverage(dfy: pd.DataFrame, candidates: List[str]) -> Tuple[str | None, pd.Series | None, Dict[str, int]]:
    """Pick a *plain* benchmark ticker deterministically.

    To keep results stable and easy to compare across runs, we select the FIRST candidate
    in the provided list that has any non-missing observations.

    We still record the non-missing counts for all candidates in the RATE_COVERAGE sheet.
    """
    coverage: Dict[str, int] = {}
    for tk in candidates:
        if tk in dfy.columns:
            coverage[tk] = int(dfy[tk].notna().sum())
        else:
            coverage[tk] = 0

    if not coverage:
        return None, None, coverage

    for tk in candidates:
        if coverage.get(tk, 0) > 0:
            return tk, dfy[tk], coverage

    return None, None, coverage

# ---------------- Build universe ----------------
all_pairs = unique_preserve_order([p for tri in pair_sets.values() for p in tri])
currencies = currencies_from_pairs(all_pairs)

print("QUAL:", QUAL)
print("Pairs:", all_pairs)
print("Currencies:", currencies)

# ---------------- Download yields (per currency) ----------------
rates: Dict[Tuple[str, str], pd.Series] = {}
chosen_tickers: Dict[Tuple[str, str], str] = {}
coverage_rows = []

for ccy in currencies:
    for t in tenors:
        cands = build_rate_candidates(ccy, t)
        if not cands:
            print(f"[{ccy} {t}] No comparable benchmark mapping. Skipping.")
            continue

        dfy = blp.bdh(cands, "PX_LAST", start_date=start, end_date=end)
        dfy = flatten_cols(dfy)

        best_tk, best_series, cov = choose_best_coverage(dfy, cands)

        # Save coverage diagnostics
        for tk, nobs in cov.items():
            coverage_rows.append(
                {"ccy": ccy, "tenor": t, "candidate": tk, "non_missing_obs": nobs, "selected": tk == best_tk}
            )

        if best_tk is None or best_series is None:
            print(f"[{ccy} {t}] All candidates empty (no data).")
            continue

        chosen_tickers[(ccy, t)] = best_tk
        rates[(ccy, t)] = (best_series / 100.0).rename(f"{ccy}_{t}")

# ---------------- Download spot FX (with qualifier) ----------------
spot_tickers = [f"{p} {QUAL} Curncy" for p in all_pairs]
spot_df = blp.bdh(spot_tickers, "PX_LAST", start_date=start, end_date=end)
spot_df = flatten_cols(spot_df)
spot_df = spot_df.rename(columns={f"{p} {QUAL} Curncy": p for p in all_pairs})

# ---------------- Document EOD snap time (timestamp) ----------------
eod_df = blp.bdp(spot_tickers, ["TRADING_DAY_END_TIME_EOD"])
eod_df = flatten_cols(eod_df).reset_index()
eod_df.columns = ["security", "TRADING_DAY_END_TIME_EOD"]
eod_df["QUAL"] = QUAL

# ---------------- Build pair sheets ----------------
sheets: Dict[str, pd.DataFrame] = {}

for pair in all_pairs:
    base, quote = pair[:3], pair[3:]

    if pair not in spot_df.columns:
        print(f"[{pair}] Missing spot column.")
        continue

    # require rates for base & quote at both tenors
    missing = []
    for ccy in (base, quote):
        for t in tenors:
            if (ccy, t) not in rates:
                missing.append((ccy, t))
    if missing:
        print(f"[{pair}] Missing comparable rates: {missing} (skip pair)")
        continue

    spot = spot_df[pair].rename("spot")

    df_base_1m  = df_simple(rates[(base, "1M")], tau["1M"])
    df_quote_1m = df_simple(rates[(quote, "1M")], tau["1M"])
    df_base_3m  = df_simple(rates[(base, "3M")], tau["3M"])
    df_quote_3m = df_simple(rates[(quote, "3M")], tau["3M"])

    fwd_1m = (spot * (df_base_1m / df_quote_1m)).rename("F_1M")
    fwd_3m = (spot * (df_base_3m / df_quote_3m)).rename("F_3M")

    sheet = pd.concat(
        [
            spot,
            rates[(base, "1M")].rename(f"r_f_{base}_1M"),
            rates[(quote, "1M")].rename(f"r_d_{quote}_1M"),
            fwd_1m,
            rates[(base, "3M")].rename(f"r_f_{base}_3M"),
            rates[(quote, "3M")].rename(f"r_d_{quote}_3M"),
            fwd_3m,
        ],
        axis=1,
    )

    # Keep rows where spot exists (don’t destroy sample due to missing rates on some days)
    sheet = sheet.dropna(subset=["spot"])
    sheet = sheet.reset_index().rename(columns={"index": "date"})

    sheets[pair] = sheet

# ---------------- Meta sheets: chosen tickers + coverage diagnostics ----------------
meta = pd.DataFrame(
    [{"ccy": ccy, "tenor": t, "chosen_bbg_ticker": tk}
     for (ccy, t), tk in sorted(chosen_tickers.items())]
)

coverage_df = pd.DataFrame(coverage_rows).sort_values(["ccy", "tenor", "selected"], ascending=[True, True, False])

# ---------------- Write Excel (IMPORTANT: index=False) ----------------
with pd.ExcelWriter(out_xlsx, engine="openpyxl") as xw:
    meta.to_excel(xw, sheet_name="TICKERS_USED", index=False)
    coverage_df.to_excel(xw, sheet_name="RATE_COVERAGE", index=False)
    eod_df.to_excel(xw, sheet_name="EOD_TIMES", index=False)
    for pair, df_pair in sheets.items():
        df_pair.to_excel(xw, sheet_name=pair, index=False)

print(f"Saved: {out_xlsx}")
print(f"Sheets written: {len(sheets)} / {len(all_pairs)} pairs")
