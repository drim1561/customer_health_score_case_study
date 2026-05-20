-- Singular test: every 'Urgent' renewal account must have a 'Critical' health tier.
--
-- By definition: Urgent = renewal within 90 days AND composite_score < 40 (Critical).
-- If an account is flagged Urgent but not Critical, the tier/urgency logic has
-- diverged — this test catches that inconsistency before CSMs act on bad data.

select
    account_id,
    health_tier,
    renewal_urgency,
    composite_health_score,
    days_to_renewal

from {{ ref('customer_health_score') }}

where
    renewal_urgency = 'Urgent'
    and health_tier != 'Critical'
