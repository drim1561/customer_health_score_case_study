-- One row per account combining CRM metadata with subscription summaries.
-- This is the "spine" every other intermediate model joins back to.

with accounts as (

    select * from {{ ref('stg_accounts') }}

),

subscription_summary as (

    -- Aggregate subscriptions to account level.
    -- COUNT(DISTINCT product): how many products this account subscribes to.
    -- Used later to compute what fraction they're actually using.
    select
        account_id,
        sum(arr_usd) as total_arr,
        count(distinct product) as products_subscribed
    from {{ ref('stg_subscriptions') }}
    group by account_id

)

select
    a.account_id,
    a.account_name,
    a.division,
    a.region,
    a.segment,
    a.country,
    a.customer_since,
    a.csm_owner,
    a.renewal_date,

    -- DATEDIFF counts whole calendar days between the two dates.
    -- Positive = renewal is in the future; negative = already past due.
    datediff('day', '2025-06-30'::date, a.renewal_date) as days_to_renewal,

    coalesce(s.total_arr, 0) as total_arr,
    coalesce(s.products_subscribed, 0) as products_subscribed

from accounts as a
-- LEFT JOIN keeps accounts with no active subscriptions (possible for
-- legacy Salesforce records that haven't been cleaned up)
left join subscription_summary as s on a.account_id = s.account_id
