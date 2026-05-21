-- Cleans the raw submissions seed table.
-- Drops 8 submissions from ghost accounts (not in accounts table).

with source as (

    select * from {{ source('raw', 'submissions') }}

),

accounts as (

    select account_id from {{ ref('stg_accounts') }}

),

cleaned as (

    select
        sm.submission_id,
        sm.submission_date::date as submission_date,
        sm.submission_timestamp::timestamp_ntz as submission_timestamp,
        sm.account_id,
        sm.product,
        sm.user_id

    from source as sm
    -- INNER JOIN silently drops the 8 ghost-account submissions
    inner join accounts as a on sm.account_id = a.account_id

    -- QUALIFY is Snowflake syntax for filtering on a window function result
    -- without needing a subquery. ROW_NUMBER() assigns 1 to the first row
    -- per submission_id; keeping only = 1 removes exact duplicates.
    -- Investigation confirmed all 15 dupes are fully identical rows
    -- (same timestamp, user, account, product) — safe to deduplicate.
    qualify row_number() over (
        partition by submission_id
        order by submission_timestamp
    ) = 1

)

select * from cleaned
