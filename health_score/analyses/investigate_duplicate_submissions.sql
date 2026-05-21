-- Investigates the 15 duplicate submission_ids found by dbt test.
-- Are they exact duplicates (same row twice) or conflicting records
-- (same ID, different field values)?

-- Step 1: find the duplicate IDs
with dupes as (
    select
        submission_id,
        count(*) as occurrences
    from {{ ref('stg_submissions') }}
    group by submission_id
    having count(*) > 1
)

-- Step 2: pull the full rows for each duplicate ID
select s.*
from {{ ref('stg_submissions') }} as s
inner join dupes as d on s.submission_id = d.submission_id
order by s.submission_id, s.submission_date
