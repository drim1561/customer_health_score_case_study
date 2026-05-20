-- Cleans the raw accounts seed table.
-- Fixes division casing, fills missing regions, excludes null account IDs.
--
-- source() tells dbt where to find raw tables that already exist in the warehouse.
-- Using source() instead of a hardcoded table name means dbt:
--   1. Knows the dependency order (builds this after the source is available)
--   2. Automatically uses the right database/schema for any environment

with source as (

    select * from {{ source('raw', 'accounts') }}

),

cleaned as (

    select
        account_id,
        account_name,

        -- Normalize the three division variants to exactly two values
        case
            when lower(division) in ('higher ed', 'highered') then 'Higher Ed'
            when lower(division) = 'k12'                      then 'K12'
            else division
        end                                          as division,

        -- 6 accounts have null region; coalesce keeps them in rollups
        coalesce(region, 'Unknown')                  as region,

        segment,
        country,
        customer_since::date                         as customer_since,
        csm_owner,
        renewal_date::date                           as renewal_date

    from source
    where account_id is not null

)

select * from cleaned
