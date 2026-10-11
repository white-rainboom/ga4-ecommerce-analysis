-- =========================================================
-- 01_data_quality.sql
-- Data quality checks for GA4 ecommerce analysis
-- Period: 2020-11-01 to 2021-01-31
-- =========================================================


-- =========================================================
-- 1. Dataset coverage
-- Goal: confirm table count and date coverage.
-- =========================================================

SELECT
  COUNT(*) AS table_count,
  MIN(REPLACE(table_name, 'events_', '')) AS min_date,
  MAX(REPLACE(table_name, 'events_', '')) AS max_date
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.INFORMATION_SCHEMA.TABLES`
WHERE table_name LIKE 'events_%';


-- =========================================================
-- 2. Event-level uniqueness
-- Goal: check whether
-- user_pseudo_id + event_timestamp + event_name
-- uniquely identifies an event in this sample.
-- =========================================================

SELECT
  user_pseudo_id,
  event_timestamp,
  event_name,
  COUNT(*) AS duplicate_count
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
GROUP BY
  user_pseudo_id,
  event_timestamp,
  event_name
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;


-- =========================================================
-- 3. Transaction ID quality
-- Goal: assess whether transaction_id can be used as
-- a reliable order identifier.
-- =========================================================

SELECT
  COUNT(*) AS purchase_events,

  COUNTIF(
    ecommerce.transaction_id IS NULL
  ) AS null_transaction_id,

  COUNTIF(
    ecommerce.transaction_id = '(not set)'
  ) AS not_set_transaction_id,

  COUNT(
    DISTINCT CASE
      WHEN ecommerce.transaction_id IS NOT NULL
       AND ecommerce.transaction_id != '(not set)'
      THEN ecommerce.transaction_id
    END
  ) AS valid_distinct_transaction_ids

FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND event_name = 'purchase';


-- =========================================================
-- 4. Repeated transaction IDs
-- Goal: check whether the same transaction_id appears
-- multiple times across users or dates.
-- =========================================================

SELECT
  ecommerce.transaction_id AS transaction_id,
  COUNT(*) AS event_count,
  COUNT(DISTINCT user_pseudo_id) AS user_count,
  COUNT(DISTINCT event_date) AS date_count
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND event_name = 'purchase'
  AND ecommerce.transaction_id IS NOT NULL
  AND ecommerce.transaction_id != '(not set)'
GROUP BY transaction_id
HAVING COUNT(*) > 1
ORDER BY event_count DESC;


-- =========================================================
-- 5. Purchase duplicate timing
-- Goal: inspect repeated purchases for the same user
-- and transaction_id and calculate time gaps.
-- =========================================================

WITH purchases AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
    AND ecommerce.transaction_id != '(not set)'
),

with_previous AS (
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

pairs AS (
  SELECT
    *,
    (event_timestamp - previous_timestamp) / 1000000.0
      AS seconds_apart
  FROM with_previous
  WHERE previous_timestamp IS NOT NULL
)

SELECT
  CASE
    WHEN seconds_apart <= 0.1 THEN '<=0.1s'
    WHEN seconds_apart <= 1 THEN '0.1-1s'
    WHEN seconds_apart <= 10 THEN '1-10s'
    WHEN seconds_apart <= 60 THEN '10-60s'
    WHEN seconds_apart <= 3600 THEN '1-60min'
    ELSE '>1h'
  END AS time_bucket,

  COUNT(*) AS pair_count

FROM pairs
GROUP BY time_bucket
ORDER BY pair_count DESC;


-- =========================================================
-- 6. Duplicate cluster size
-- Goal: check whether repeated purchases usually occur
-- twice or in larger clusters.
-- Note: this groups same user + transaction_id + revenue,
-- regardless of time gap.
-- =========================================================

WITH cnt AS (
  SELECT
    user_pseudo_id,
    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS revenue,
    COUNT(*) AS event_count
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
    AND ecommerce.transaction_id IS NOT NULL
    AND ecommerce.transaction_id != '(not set)'
  GROUP BY
    user_pseudo_id,
    transaction_id,
    revenue
  HAVING COUNT(*) > 1
)

SELECT
  event_count,
  COUNT(*) AS group_count
FROM cnt
GROUP BY event_count
ORDER BY event_count;


-- =========================================================
-- 7. Deduplication sensitivity analysis
-- Goal: compare 0.1s, 1s, and 5s thresholds.
-- Rule:
-- same user + same transaction_id + same revenue
-- within threshold => probable duplicate.
-- =========================================================

WITH purchases AS (
  SELECT
    user_pseudo_id,
    event_timestamp,
    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
),

with_previous AS (
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

purchase_pairs AS (
  SELECT
    *,
    CASE
      WHEN previous_timestamp IS NULL THEN NULL
      ELSE (event_timestamp - previous_timestamp) / 1000000.0
    END AS seconds_apart
  FROM with_previous
),

flagged AS (
  SELECT
    *,

    CASE
      WHEN seconds_apart IS NOT NULL
       AND seconds_apart <= 0.1
       AND revenue = previous_revenue
      THEN 0 ELSE 1
    END AS keep_01s,

    CASE
      WHEN seconds_apart IS NOT NULL
       AND seconds_apart <= 1
       AND revenue = previous_revenue
      THEN 0 ELSE 1
    END AS keep_1s,

    CASE
      WHEN seconds_apart IS NOT NULL
       AND seconds_apart <= 5
       AND revenue = previous_revenue
      THEN 0 ELSE 1
    END AS keep_5s

  FROM purchase_pairs
)

SELECT
  'no_dedup' AS rule,
  COUNT(*) AS orders,
  SUM(revenue) AS revenue,
  SAFE_DIVIDE(SUM(revenue), COUNTIF(revenue IS NOT NULL)) AS aov
FROM flagged

UNION ALL

SELECT
  '0.1s' AS rule,
  COUNTIF(keep_01s = 1) AS orders,
  SUM(IF(keep_01s = 1, revenue, NULL)) AS revenue,
  SAFE_DIVIDE(
    SUM(IF(keep_01s = 1, revenue, NULL)),
    COUNTIF(keep_01s = 1 AND revenue IS NOT NULL)
  ) AS aov
FROM flagged

UNION ALL

SELECT
  '1s' AS rule,
  COUNTIF(keep_1s = 1) AS orders,
  SUM(IF(keep_1s = 1, revenue, NULL)) AS revenue,
  SAFE_DIVIDE(
    SUM(IF(keep_1s = 1, revenue, NULL)),
    COUNTIF(keep_1s = 1 AND revenue IS NOT NULL)
  ) AS aov
FROM flagged

UNION ALL

SELECT
  '5s' AS rule,
  COUNTIF(keep_5s = 1) AS orders,
  SUM(IF(keep_5s = 1, revenue, NULL)) AS revenue,
  SAFE_DIVIDE(
    SUM(IF(keep_5s = 1, revenue, NULL)),
    COUNTIF(keep_5s = 1 AND revenue IS NOT NULL)
  ) AS aov
FROM flagged;


-- =========================================================
-- 8. Revenue completeness by date
-- Goal: quantify missing purchase_revenue by date.
-- =========================================================

SELECT
  event_date,
  COUNT(*) AS purchase_events,
  COUNTIF(
    ecommerce.purchase_revenue IS NULL
  ) AS null_revenue_events,

  SAFE_DIVIDE(
    COUNTIF(ecommerce.purchase_revenue IS NULL),
    COUNT(*)
  ) AS revenue_missing_rate

FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND event_name = 'purchase'
GROUP BY event_date
HAVING null_revenue_events > 0
ORDER BY event_date;


-- =========================================================
-- 9. Revenue recoverability using item_revenue
-- Goal: test whether missing purchase_revenue can be
-- recovered from item-level revenue.
-- =========================================================

WITH purchase_revenue_check AS (
  SELECT
    event_date,
    ecommerce.purchase_revenue AS purchase_revenue,

    (
      SELECT SUM(item.item_revenue)
      FROM UNNEST(items) AS item
    ) AS items_revenue

  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name = 'purchase'
)

SELECT
  COUNT(*) AS missing_purchase_revenue,

  COUNTIF(
    items_revenue IS NOT NULL
  ) AS recoverable_with_items,

  COUNTIF(
    items_revenue IS NULL
  ) AS still_missing,

  SAFE_DIVIDE(
    COUNTIF(items_revenue IS NOT NULL),
    COUNT(*)
  ) AS recovery_rate

FROM purchase_revenue_check
WHERE purchase_revenue IS NULL;


-- =========================================================
-- Final decisions
-- =========================================================

-- 1. user_pseudo_id + event_timestamp + event_name
--    is unique in the observed sample and can be used as
--    an event-level composite identifier for this project.
--
-- 2. transaction_id is not a reliable global order key:
--    it contains NULL / '(not set)' values and can repeat
--    across users and dates.
--
-- 3. Purchase events with the same user, transaction_id,
--    and revenue occurring within 1 second are treated as
--    probable duplicates.
--
-- 4. Sensitivity tests using 0.1s / 1s / 5s thresholds
--    produce very similar results, supporting the 1s rule.
--
-- 5. Some purchase events have missing purchase_revenue.
--    These records remain usable for user/order/conversion
--    analysis but not for complete revenue measurement.
--
-- 6. Missing purchase_revenue cannot be reliably recovered
--    from items.item_revenue in this dataset.