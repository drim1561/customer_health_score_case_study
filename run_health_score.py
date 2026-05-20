import duckdb
import pandas as pd

pd.set_option('display.max_columns', 20)
pd.set_option('display.width', 140)
pd.set_option('display.float_format', '{:.1f}'.format)

con = duckdb.connect()
con.execute("CREATE TABLE accounts      AS SELECT * FROM read_csv_auto('data/accounts.csv')")
con.execute("CREATE TABLE subscriptions AS SELECT * FROM read_csv_auto('data/subscriptions.csv')")
con.execute("CREATE TABLE submissions   AS SELECT * FROM read_csv_auto('data/submissions.csv')")

with open('health_score.sql') as f:
    sql = f.read()

df = con.execute(sql).fetchdf()

print(f"Total accounts scored: {len(df)}")
print(f"Total ARR covered:     ${df['total_arr'].sum():,.0f}")
print()

# ── Tier distribution ──────────────────────────────────────────────────────────
print("=== HEALTH TIER DISTRIBUTION ===")
tier_counts = df['health_tier'].value_counts()
tier_arr    = df.groupby('health_tier')['total_arr'].sum()
tier_summary = pd.DataFrame({'accounts': tier_counts, 'total_arr': tier_arr})
tier_summary['arr_pct'] = tier_summary['total_arr'] / df['total_arr'].sum() * 100
print(tier_summary.to_string())
print()

# ── Tier by division ──────────────────────────────────────────────────────────
print("=== TIER BY DIVISION ===")
print(df.groupby(['division','health_tier']).size().unstack(fill_value=0).to_string())
print()

# ── Tier by segment ───────────────────────────────────────────────────────────
print("=== TIER BY SEGMENT ===")
print(df.groupby(['segment','health_tier']).size().unstack(fill_value=0).to_string())
print()

# ── Renewal urgency ───────────────────────────────────────────────────────────
print("=== RENEWAL URGENCY ===")
print(df['renewal_urgency'].value_counts().to_string())
print()

# ── Critical & At Risk accounts ───────────────────────────────────────────────
print("=== CRITICAL & AT-RISK ACCOUNTS ===")
cols = ['account_name','division','segment','total_arr','composite_health_score',
        'health_tier','renewal_urgency','days_to_renewal','recent_mau','days_since_last_submission']
print(df[df['health_tier'].isin(['Critical','At Risk'])][cols].to_string(index=False))
print()

# ── Bottom-quartile healthy accounts (peer percentile < 25) ──────────────────
print("=== HEALTHY ACCOUNTS IN BOTTOM QUARTILE OF PEER GROUP (peer_percentile_rank < 25) ===")
bottom_q = df[(df['health_tier'] == 'Healthy') & (df['peer_percentile_rank'] < 25)]
cols2 = ['account_name','division','segment','total_arr','composite_health_score',
         'peer_percentile_rank','renewal_urgency','days_to_renewal','recent_mau']
print(f"{len(bottom_q)} accounts  |  ARR: ${bottom_q['total_arr'].sum():,.0f}")
print(bottom_q.sort_values('peer_percentile_rank')[cols2].head(20).to_string(index=False))
print()

# ── Score component stats ─────────────────────────────────────────────────────
print("=== SCORE COMPONENT SUMMARY ===")
print(df[['composite_health_score','submission_trend_score','mau_trend_score',
          'recency_score','product_adoption_score','relative_activity_score']]
      .describe().round(1).to_string())
print()

# ── ARR at risk ───────────────────────────────────────────────────────────────
at_risk_arr = df[df['health_tier'].isin(['Critical','At Risk'])]['total_arr'].sum()
total_arr   = df['total_arr'].sum()
print(f"=== ARR AT RISK ===")
print(f"At-risk ARR (Critical+At Risk): ${at_risk_arr:,.0f}  ({at_risk_arr/total_arr*100:.1f}% of total)")
print(f"Total ARR:                      ${total_arr:,.0f}")
print()

# ── Expansion candidates: healthy + growing MAU ───────────────────────────────
print("=== EXPANSION CANDIDATES (Healthy + MAU growing 20%+) ===")
expansion = df[
    (df['health_tier'] == 'Healthy') &
    (df['prior_mau'] > 0) &
    (df['recent_mau'] / df['prior_mau'] >= 1.2) &
    (df['products_subscribed'] < 3)            # room to expand to more products
].sort_values('total_arr', ascending=False)
cols3 = ['account_name','division','segment','total_arr','products_subscribed',
         'recent_mau','prior_mau','composite_health_score']
print(f"{len(expansion)} accounts")
print(expansion[cols3].head(15).to_string(index=False))
print()

df.to_csv('customer_health_score.csv', index=False)
print("Full results saved to customer_health_score.csv")
