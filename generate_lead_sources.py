"""
Generates a synthetic `lead_sources.csv` table that extends the real
Maven Analytics "CRM Sales Opportunities" dataset with upstream
marketing-funnel data (lead source, lead score, MQL/SQL timestamps).

WHY THIS EXISTS:
The real dataset only captures CRM/pipeline-side stages (Prospecting,
Engaging, Won, Lost). It has no marketing-attribution data — no real
company publishes that, since it reveals CAC and channel economics.
This script fills that gap with a *documented*
synthetic layer so the funnel can be analyzed end-to-end (lead source
-> MQL -> SQL -> pipeline opportunity), which the real dataset alone
cannot answer.

The channel mix and quality skew below are my own assumptions for a B2B hardware
seller. They are not calibrated to published conversion benchmarks.

Design choices (documented, not hidden):
  - Lead source mix skewed for enterprise/B2B hardware selling motion
    (Referral/Partner high quality & low volume, Outbound high volume
    & low quality, Paid Ads lowest quality).
  - Lead score correlated with source quality AND with deal outcome,
    so lead quality visibly affects results in this simulated data.
  - A handful of reps are deliberately given above-average conversion
    on low-quality (Outbound) leads -- these are the "hidden gems" the
    analysis should surface.
"""
import pandas as pd
import numpy as np

np.random.seed(42)

sp = pd.read_csv("sales_pipeline.csv", parse_dates=["engage_date", "close_date"])

# --- 1. Lead source mix (enterprise B2B hardware skew) ---------------------
SOURCES = ["Referral", "Partner", "Outbound", "Webinar", "Organic Search", "Paid Ads"]
SOURCE_WEIGHTS = [0.22, 0.15, 0.25, 0.14, 0.16, 0.08]

# Base quality score (0-100) by source -- used to bias lead_score
SOURCE_QUALITY_BASE = {
    "Referral": 78, "Partner": 72, "Webinar": 58,
    "Organic Search": 55, "Outbound": 42, "Paid Ads": 35,
}

n = len(sp)

# Assign lead_source conditioned on real deal_stage so outcome actually
# correlates with source quality (not just with lead_score in isolation).
# Base mix is the target distribution; we then tilt per-stage using
# multiplicative weights so Won skews toward high-quality sources and
# Lost skews toward low-quality sources, while keeping the OVERALL mix
# close to the intended enterprise B2B split.
STAGE_TILT = {
    "Won":         {"Referral": 1.6, "Partner": 1.4, "Webinar": 1.0, "Organic Search": 0.9, "Outbound": 0.6, "Paid Ads": 0.4},
    "Lost":        {"Referral": 0.5, "Partner": 0.6, "Webinar": 0.9, "Organic Search": 1.0, "Outbound": 1.5, "Paid Ads": 1.7},
    "Engaging":    {"Referral": 1.1, "Partner": 1.0, "Webinar": 1.0, "Organic Search": 1.0, "Outbound": 0.95, "Paid Ads": 0.9},
    "Prospecting": {"Referral": 1.0, "Partner": 1.0, "Webinar": 1.0, "Organic Search": 1.0, "Outbound": 1.0, "Paid Ads": 1.0},
}

lead_source = np.empty(n, dtype=object)
base_w = np.array(SOURCE_WEIGHTS)
for stage, tilt in STAGE_TILT.items():
    mask = (sp["deal_stage"].values == stage)
    n_stage = mask.sum()
    if n_stage == 0:
        continue
    tilted = base_w * np.array([tilt[s] for s in SOURCES])
    tilted = tilted / tilted.sum()
    lead_source[mask] = np.random.choice(SOURCES, size=n_stage, p=tilted)

# --- 2. Lead score: source quality + noise + small bump if deal was Won ----
base_quality = np.array([SOURCE_QUALITY_BASE[s] for s in lead_source])
noise = np.random.normal(0, 12, size=n)
won_bump = np.where(sp["deal_stage"].values == "Won", np.random.uniform(3, 10, n), 0)
lead_score = np.clip(base_quality + noise + won_bump, 1, 100).round(1)

# --- 3. "Hidden gem" reps: convert Outbound leads unusually well ----------
rep_skill_bonus = {}
all_agents = sp["sales_agent"].unique()
hidden_gems = np.random.choice(all_agents, size=4, replace=False)
for agent in hidden_gems:
    rep_skill_bonus[agent] = np.random.uniform(15, 25)  # extra pts on Outbound leads

for i, (agent, src) in enumerate(zip(sp["sales_agent"].values, lead_source)):
    if src == "Outbound" and agent in rep_skill_bonus:
        lead_score[i] = np.clip(lead_score[i] + rep_skill_bonus[agent], 1, 100)

# --- 4. Synthetic MQL / SQL dates, backdated from engage_date --------------
# Only assign upstream dates where engage_date exists (mirrors real nulls)
mql_date = pd.Series(pd.NaT, index=sp.index, dtype="datetime64[ns]")
sql_date = pd.Series(pd.NaT, index=sp.index, dtype="datetime64[ns]")

has_engage = sp["engage_date"].notna()
lead_to_mql_days = np.random.randint(3, 21, size=n)      # 3-20 days lead->MQL
mql_to_sql_days = np.random.randint(2, 15, size=n)       # 2-14 days MQL->SQL
sql_to_engage_days = np.random.randint(1, 10, size=n)    # 1-9 days SQL->engage

sql_date_calc = sp["engage_date"] - pd.to_timedelta(sql_to_engage_days, unit="D")
mql_date_calc = sql_date_calc - pd.to_timedelta(mql_to_sql_days, unit="D")
lead_date_calc = mql_date_calc - pd.to_timedelta(lead_to_mql_days, unit="D")

mql_date[has_engage] = mql_date_calc[has_engage]
sql_date[has_engage] = sql_date_calc[has_engage]
lead_created_date = pd.Series(pd.NaT, index=sp.index, dtype="datetime64[ns]")
lead_created_date[has_engage] = lead_date_calc[has_engage]

# --- 5. Marketing spend per lead (for later CAC-style analysis) -----------
SOURCE_CPL = {  # rough relative cost-per-lead, INR, illustrative
    "Referral": 200, "Partner": 500, "Webinar": 1500,
    "Organic Search": 300, "Outbound": 800, "Paid Ads": 2200,
}
cost_per_lead = np.array([SOURCE_CPL[s] * np.random.uniform(0.85, 1.15) for s in lead_source]).round(0)

out = pd.DataFrame({
    "opportunity_id": sp["opportunity_id"],
    "lead_source": lead_source,
    "lead_score": lead_score,
    "cost_per_lead_inr": cost_per_lead,
    "lead_created_date": lead_created_date,
    "mql_date": mql_date,
    "sql_date": sql_date,
})

out.to_csv("lead_sources.csv", index=False)
print(out.head(10).to_string())
print("\nRows:", len(out))
print("\nLead source distribution:\n", out["lead_source"].value_counts(normalize=True).round(3))
print("\nHidden-gem reps (unusually good at converting Outbound leads):", list(hidden_gems))
