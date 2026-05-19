# Schema Reference

All three files are in `/data` as CSVs with a header row.

---

## `accounts.csv`
One row per Salesforce account.

| Column | Type | Description |
|---|---|---|
| `account_id` | string | Primary key. Format `ACC-XXXX`. |
| `account_name` | string | Display name of the institution. |
| `division` | string | `K12` or `Higher Ed`. *(Heads up: casing may vary in the source.)* |
| `region` | string | `NAM`, `EMEA`, `APAC`, or `LATAM`. May be missing for some legacy records. |
| `segment` | string | For Higher Ed: `Enterprise`, `Mid-Market`, `SMB`. For K12: `District`, `School`, `Charter Network`. |
| `country` | string | ISO-style country name. |
| `customer_since` | date | First contract start date. |
| `csm_owner` | string | Assigned Customer Success Manager. May be blank for unassigned accounts. |
| `renewal_date` | date | Next upcoming renewal. |

---

## `subscriptions.csv`
One row per active product subscription. An account can have multiple rows (one per product).

| Column | Type | Description |
|---|---|---|
| `subscription_id` | string | Primary key. Format `SUB-XXXXX`. |
| `account_id` | string | Foreign key to `accounts.account_id`. |
| `product` | string | One of `Originality`, `Feedback Studio`, `Gradescope`. |
| `arr_usd` | decimal | Annual Recurring Revenue for this subscription, in USD. |
| `term_start_date` | date | Current term start. |
| `term_end_date` | date | Current term end (= renewal date for the subscription). |
| `status` | string | `Active` for all rows in this extract. |

---

## `submissions.csv`
One row per submission event. This is the primary product engagement event.

| Column | Type | Description |
|---|---|---|
| `submission_id` | string | Unique identifier per submission event. Format `SBM-XXXXXXXX`. |
| `submission_date` | date | Day of submission (UTC). |
| `submission_timestamp` | datetime | ISO-8601 timestamp (UTC) of submission. |
| `account_id` | string | Foreign key to `accounts.account_id`. |
| `product` | string | One of `Originality`, `Feedback Studio`, `Gradescope`. |
| `user_id` | string | Identifier for the submitting user. Stable per account-product (a user keeps the same ID over time). Format `USR-{acct_suffix}-{product_code}-{seq}`. |

Date range: **2024-01-01 through 2025-06-30**.

> **Active users are not provided as a pre-aggregated table.** You'll derive them from `user_id` here. The grain you choose (DAU, WAU, MAU, MQU) is your call — pick what makes sense for the analysis and document it.

---

## Relationships

```
accounts (1) ──< (N) subscriptions
accounts (1) ──< (N) submissions
```

Both `subscriptions` and `submissions` join to `accounts` on `account_id`. There is no direct join between `subscriptions` and `submissions` — combine them through `accounts`, or by `(account_id, product)` if you want product-level joins.

`user_id` is unique within an `(account_id, product)` pair, but the same physical person could appear with different IDs across products (the source systems don't share a user identity layer).

---

## A Few Things Worth Knowing

- **The fiscal year ends in June.** Most renewals cluster around July–August.
- **Submissions are heavily seasonal.** K12 has a strong summer trough; Higher Ed peaks at end-of-semester (Apr–May, Nov–Dec).
- **Not every account uses every product.** Originality has the broadest adoption; Gradescope is more concentrated in Higher Ed STEM.
- **Submissions skew toward weekdays and academic working hours**, with most activity 9am–5pm local-time-ish (timestamps are UTC, no localization applied).
- **The data was extracted as-is from production.** No cleaning has been applied.
