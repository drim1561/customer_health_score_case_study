# Customer Health Score — BI Engineer Case Study

## Welcome

Thanks for taking the time to work through this case study. We've designed it to mirror the kind of work you'd do day-to-day on our team: take messy, real-world data, build a defensible model, and tell a story that helps the business act.

**Time expectation: ~3-4 hours.** This assumes heavy use of AI tooling (Cursor, Claude, ChatGPT, Copilot — your choice) for schema exploration, query writing, and analysis. We're not testing whether you can write SQL from memory; we're testing how you scope a problem, structure a solution, and communicate it.

---

## The Scenario

You've just joined the BI team at an edtech company that sells writing-integrity, feedback, and grading products to K12 districts and Higher Education institutions globally. Customer Success has been asking for a **Customer Health Score** — a single composite metric that helps CSMs and leadership understand which accounts are healthy, at risk, or thriving.

Today, the CS team eyeballs usage in dashboards and relies on gut feel. Renewals are coming up and leadership wants a more systematic way to:

1. Identify accounts at risk of churn or downsell **before** the renewal conversation
2. Spot expansion candidates
3. Understand what "healthy" looks like across different segments (you can't compare a 50-seat charter school to a 5,000-seat R1 university with the same yardstick)

You've been given access to product event data and a Salesforce extract.

---

## What You're Working With

Three CSV files in `/data`:

| File | Description | Approx rows |
|---|---|---|
| `accounts.csv` | Salesforce account dimensions (region, division, segment, CSM owner, etc.) | ~325 |
| `subscriptions.csv` | Active subscriptions by account-product with ARR | ~570 |
| `submissions.csv` | Row-per-submission event data with user_id (Jan 2024 – Jun 2025) | ~435K |

See `schema.md` for full column definitions and notes.

**Submissions and active users are both top-level KPIs at this company.** Note that you only have raw submission events — to get to active users (DAU / WAU / MAU), you'll need to derive them from `user_id` in the submissions table. How you define "active" is up to you; document your choice.

**A note on data quality:** This data was pulled from production systems. It is *not* clean. Treat anything you'd treat in a real extract — investigate, document what you find, and decide how to handle it.

---

## Products

The company sells three products. You'll see all three in the data:

- **Originality** — plagiarism / AI-writing detection. The flagship; broad adoption across both K12 and Higher Ed.
- **Feedback Studio** — instructor feedback and rubric-based grading on student writing.
- **Gradescope** — assignment authoring and AI-assisted grading, especially strong in STEM Higher Ed.

Submissions are tracked per product. Accounts can have any combination of the three.

---

## What We'd Like You to Deliver

### 1. SQL model(s) for the health score *(required)*

A SQL file (or set of files) that:
- Reads from the three source tables
- Produces a final `customer_health_score` table with one row per account, including:
  - The composite score
  - Component sub-scores (so it's interpretable)
  - The dimensions needed for slicing (region, division, segment, ARR, etc.)
- Is something a teammate could pick up and run

You can use any SQL dialect you're comfortable with (Postgres, Snowflake, BigQuery, DuckDB all fine — just tell us which). If you'd rather build it in dbt, Python/pandas, or a notebook, that's fine too — just be explicit about your choice and why.

### 2. A short presentation *(required)*

A Google Slides deck (or PDF/PPT export) with **roughly 4–6 slides** covering:
- How you defined the health score and why
- Key findings — what does the data tell us about our customer base?
- 2–3 specific recommendations the CS or product team could act on
- Any caveats, data quality issues, or things you'd improve with more time

We'd rather see 5 great slides than 10 mediocre ones. Density and clarity beat slide count.

### 3. Supporting docs *(optional but encouraged)*

Anything that helps us understand your thinking — a README, a data quality memo, an entity-relationship sketch, exploratory queries, etc. Bring whatever you'd normally produce.

---

## Questions to Help Point You

The brief is open-ended on purpose, but if you'd like some anchors:

- **How do you compare a small SMB to a large Enterprise account fairly?** Raw submission counts will always favor large customers. What's the right normalization?
- **The data spans 18 months across an academic calendar.** How does seasonality affect what "declining" means? A 40% drop from May to July might be totally normal.
- **Which accounts are at risk right now**, and is that risk concentrated in any region, division, segment, or product?

You don't need to answer all of these. Pick the threads you find most interesting and run with them.

---

## How We'll Evaluate

We're looking at:

1. **Data exploration & quality** — Did you investigate the data before modeling? Did you catch the issues that are there?
2. **Modeling judgment** — Is the health score logic defensible? Does it handle edge cases (new customers, missing data, segment differences)?
3. **SQL craft** — Is the code readable, correct, and reasonably performant? Could a teammate maintain it?
4. **Analytical depth** — Did you find something non-obvious?
5. **Storytelling** — Can a non-technical exec read your deck and know what to do next?
6. **Use of AI** — We expect heavy AI use. We're interested in *how* you direct AI tools, not whether you avoided them. Feel free to share prompts or workflow notes if you'd like.

---

## Submission

Send us a zip (or a link to a Google Drive / GitHub repo) containing:

- Your SQL / dbt / notebook files
- The slide deck (link to Google Slides is fine, or export to PDF)
- Any supporting docs you want to share

If anything is unclear before you start, please reach out. Once you're underway, feel free to make assumptions — just document them.

Good luck, and have fun with it.
