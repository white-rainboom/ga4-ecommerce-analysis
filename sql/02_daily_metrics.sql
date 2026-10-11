-- Daily e-commerce metrics
-- Source: GA4 obfuscated sample ecommerce dataset
-- Period: 2020-11-01 to 2021-01-31
--
-- Purchase deduplication:
-- For the same user and transaction_id, a purchase event is treated as
-- a probable duplicate when revenue is unchanged and the event occurs
-- within 1 second of the previous purchase event.
--
-- AOV:
-- Revenue / orders with non-null revenue only.
--
-- Note:
-- Some purchase events have missing revenue, so revenue_missing_rate
-- is retained for downstream reliability checks.

WITH daily_users AS (
  SELECT
    event_date,
    COUNT(DISTINCT user_pseudo_id) AS users
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  GROUP BY event_date
),

purchases AS (
  SELECT
    event_date,
    user_pseudo_id,
    event_timestamp,
    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
),

purchase_with_previous AS (
  SELECT
    *,
    LAG(event_timestamp) OVER (
      PARTITION BY user_pseudo_id, transaction_id
      ORDER BY event_timestamp
    ) AS previous_timestamp,

    LAG(revenue) OVER (
      PARTITION BY user_pseudo_id, transaction_id
      ORDER BY event_timestamp
    ) AS previous_revenue
  FROM purchases
),

deduped_purchases AS (
  SELECT *
  FROM purchase_with_previous
  WHERE NOT (
    previous_timestamp IS NOT NULL
    AND (event_timestamp - previous_timestamp) / 1000000.0 <= 1
    AND revenue = previous_revenue
  )
),

daily_purchase_metrics AS (
  SELECT
    event_date,
    COUNT(DISTINCT user_pseudo_id) AS purchasers,
    COUNT(*) AS orders,
    COUNTIF(revenue IS NULL) AS revenue_missing_orders,
    COUNTIF(revenue IS NOT NULL) AS revenue_known_orders,
    SUM(revenue) AS revenue
  FROM deduped_purchases
  GROUP BY event_date
)

SELECT
  u.event_date,
  u.users,
  COALESCE(p.purchasers, 0) AS purchasers,
  COALESCE(p.orders, 0) AS orders,
  p.revenue,

  SAFE_DIVIDE(
    COALESCE(p.purchasers, 0),
    u.users
  ) AS conversion_rate,

  SAFE_DIVIDE(
    p.revenue,
    p.revenue_known_orders
  ) AS aov,

  COALESCE(p.revenue_missing_orders, 0) AS revenue_missing_orders,

  SAFE_DIVIDE(
    p.revenue_missing_orders,
    p.orders
  ) AS revenue_missing_rate

FROM daily_users u
LEFT JOIN daily_purchase_metrics p
  ON u.event_date = p.event_date
ORDER BY u.event_date;