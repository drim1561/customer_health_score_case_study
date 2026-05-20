import duckdb

con = duckdb.connect()

con.execute("CREATE TABLE accounts AS SELECT * FROM read_csv_auto('data/accounts.csv')")
con.execute("CREATE TABLE subscriptions AS SELECT * FROM read_csv_auto('data/subscriptions.csv')")
con.execute("CREATE TABLE submissions AS SELECT * FROM read_csv_auto('data/submissions.csv')")

print("=" * 60)
print("ACCOUNTS")
print("=" * 60)
print(con.execute("SELECT COUNT(*) as row_count FROM accounts").fetchdf().to_string(index=False))
print()
print(con.execute("DESCRIBE accounts").fetchdf().to_string(index=False))
print()
print("-- Nulls / blanks --")
print(con.execute("""
    SELECT
      SUM(CASE WHEN account_id IS NULL OR account_id = '' THEN 1 ELSE 0 END) as account_id_nulls,
      SUM(CASE WHEN division IS NULL OR division = '' THEN 1 ELSE 0 END) as division_nulls,
      SUM(CASE WHEN region IS NULL OR region = '' THEN 1 ELSE 0 END) as region_nulls,
      SUM(CASE WHEN segment IS NULL OR segment = '' THEN 1 ELSE 0 END) as segment_nulls,
      SUM(CASE WHEN csm_owner IS NULL OR csm_owner = '' THEN 1 ELSE 0 END) as csm_owner_nulls,
      SUM(CASE WHEN renewal_date IS NULL THEN 1 ELSE 0 END) as renewal_date_nulls
    FROM accounts
""").fetchdf().to_string(index=False))
print()
print("-- Division values (case check) --")
print(con.execute("SELECT division, COUNT(*) as cnt FROM accounts GROUP BY division ORDER BY cnt DESC").fetchdf().to_string(index=False))
print()
print("-- Region values --")
print(con.execute("SELECT region, COUNT(*) as cnt FROM accounts GROUP BY region ORDER BY cnt DESC").fetchdf().to_string(index=False))
print()
print("-- Segment values --")
print(con.execute("SELECT segment, COUNT(*) as cnt FROM accounts GROUP BY segment ORDER BY cnt DESC").fetchdf().to_string(index=False))

print()
print("=" * 60)
print("SUBSCRIPTIONS")
print("=" * 60)
print(con.execute("SELECT COUNT(*) as row_count FROM subscriptions").fetchdf().to_string(index=False))
print()
print(con.execute("DESCRIBE subscriptions").fetchdf().to_string(index=False))
print()
print("-- Nulls --")
print(con.execute("""
    SELECT
      SUM(CASE WHEN account_id IS NULL THEN 1 ELSE 0 END) as account_id_nulls,
      SUM(CASE WHEN product IS NULL THEN 1 ELSE 0 END) as product_nulls,
      SUM(CASE WHEN arr_usd IS NULL THEN 1 ELSE 0 END) as arr_nulls,
      SUM(CASE WHEN arr_usd = 0 THEN 1 ELSE 0 END) as arr_zero,
      SUM(CASE WHEN arr_usd < 0 THEN 1 ELSE 0 END) as arr_negative
    FROM subscriptions
""").fetchdf().to_string(index=False))
print()
print("-- Product distribution --")
print(con.execute("SELECT product, COUNT(*) as cnt, ROUND(SUM(arr_usd),0) as total_arr FROM subscriptions GROUP BY product ORDER BY total_arr DESC").fetchdf().to_string(index=False))
print()
print("-- ARR stats --")
print(con.execute("SELECT ROUND(MIN(arr_usd),0) as min_arr, ROUND(AVG(arr_usd),0) as avg_arr, ROUND(MAX(arr_usd),0) as max_arr, ROUND(SUM(arr_usd),0) as total_arr FROM subscriptions").fetchdf().to_string(index=False))
print()
print("-- Subscriptions not joined to accounts --")
print(con.execute("SELECT COUNT(*) as orphan_subs FROM subscriptions s LEFT JOIN accounts a ON s.account_id = a.account_id WHERE a.account_id IS NULL").fetchdf().to_string(index=False))

print()
print("=" * 60)
print("SUBMISSIONS")
print("=" * 60)
print(con.execute("SELECT COUNT(*) as row_count FROM submissions").fetchdf().to_string(index=False))
print()
print(con.execute("DESCRIBE submissions").fetchdf().to_string(index=False))
print()
print("-- Date range --")
print(con.execute("SELECT MIN(submission_date) as earliest, MAX(submission_date) as latest FROM submissions").fetchdf().to_string(index=False))
print()
print("-- Nulls --")
print(con.execute("""
    SELECT
      SUM(CASE WHEN account_id IS NULL THEN 1 ELSE 0 END) as account_id_nulls,
      SUM(CASE WHEN user_id IS NULL THEN 1 ELSE 0 END) as user_id_nulls,
      SUM(CASE WHEN product IS NULL THEN 1 ELSE 0 END) as product_nulls,
      SUM(CASE WHEN submission_date IS NULL THEN 1 ELSE 0 END) as date_nulls
    FROM submissions
""").fetchdf().to_string(index=False))
print()
print("-- Product distribution --")
print(con.execute("SELECT product, COUNT(*) as submissions, COUNT(DISTINCT user_id) as unique_users, COUNT(DISTINCT account_id) as accounts FROM submissions GROUP BY product ORDER BY submissions DESC").fetchdf().to_string(index=False))
print()
print("-- Submissions with no matching account --")
print(con.execute("SELECT COUNT(*) as orphan_submissions FROM submissions s LEFT JOIN accounts a ON s.account_id = a.account_id WHERE a.account_id IS NULL").fetchdf().to_string(index=False))
print()
print("-- Accounts in submissions but not in accounts table --")
print(con.execute("SELECT COUNT(DISTINCT s.account_id) as ghost_accounts FROM submissions s LEFT JOIN accounts a ON s.account_id = a.account_id WHERE a.account_id IS NULL").fetchdf().to_string(index=False))
print()
print("-- Accounts with subscriptions but zero submissions --")
print(con.execute("""
    SELECT COUNT(DISTINCT sub.account_id) as accounts_no_submissions
    FROM subscriptions sub
    LEFT JOIN submissions sm ON sub.account_id = sm.account_id
    WHERE sm.account_id IS NULL
""").fetchdf().to_string(index=False))
