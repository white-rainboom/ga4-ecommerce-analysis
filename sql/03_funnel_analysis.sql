-- =========================================================
-- 03_funnel_analysis.sql
-- Ecommerce funnel and conversion diagnostics
-- Dataset: GA4 obfuscated sample ecommerce
-- Period: 2020-11-01 to 2021-01-31
--
-- Main questions:
-- 1. Which funnel stage deteriorated most?
-- 2. When did the deterioration begin?
-- 3. Is the decline concentrated in a major segment?
-- =========================================================


-- =========================================================
-- 1. Exploratory strict monthly funnel
--
-- Funnel:
-- view_item -> add_to_cart -> begin_checkout -> purchase
--
-- Events must occur in sequence for the same user
-- within the same month.
--
-- November add_to_cart tracking is later shown to be
-- discontinuous, so November is used for exploration rather
-- than direct business-performance comparison.
-- =========================================================

WITH base_events AS (
  SELECT
    SUBSTR(event_date, 1, 6) AS month,
    user_pseudo_id,
    event_name,
    event_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
),

monthly_users AS (
  SELECT
    month,
    COUNT(DISTINCT user_pseudo_id) AS users
  FROM base_events
  GROUP BY month
),

views AS (
  SELECT
    month,
    user_pseudo_id,
    MIN(event_timestamp) AS view_ts
  FROM base_events
  WHERE event_name = 'view_item'
  GROUP BY month, user_pseudo_id
),

carts AS (
  SELECT
    v.month,
    v.user_pseudo_id,
    MIN(e.event_timestamp) AS cart_ts
  FROM views v
  JOIN base_events e
    ON v.month = e.month
   AND v.user_pseudo_id = e.user_pseudo_id
   AND e.event_name = 'add_to_cart'
   AND e.event_timestamp > v.view_ts
  GROUP BY v.month, v.user_pseudo_id
),

checkouts AS (
  SELECT
    c.month,
    c.user_pseudo_id,
    MIN(e.event_timestamp) AS checkout_ts
  FROM carts c
  JOIN base_events e
    ON c.month = e.month
   AND c.user_pseudo_id = e.user_pseudo_id
   AND e.event_name = 'begin_checkout'
   AND e.event_timestamp > c.cart_ts
  GROUP BY c.month, c.user_pseudo_id
),

purchases AS (
  SELECT
    ch.month,
    ch.user_pseudo_id,
    MIN(e.event_timestamp) AS purchase_ts
  FROM checkouts ch
  JOIN base_events e
    ON ch.month = e.month
   AND ch.user_pseudo_id = e.user_pseudo_id
   AND e.event_name = 'purchase'
   AND e.event_timestamp > ch.checkout_ts
  GROUP BY ch.month, ch.user_pseudo_id
),

view_counts AS (
  SELECT month, COUNT(*) AS view_users
  FROM views
  GROUP BY month
),

cart_counts AS (
  SELECT month, COUNT(*) AS cart_users
  FROM carts
  GROUP BY month
),

checkout_counts AS (
  SELECT month, COUNT(*) AS checkout_users
  FROM checkouts
  GROUP BY month
),

purchase_counts AS (
  SELECT month, COUNT(*) AS purchase_users
  FROM purchases
  GROUP BY month
)

SELECT
  u.month,
  u.users,
  COALESCE(v.view_users, 0) AS view_users,
  COALESCE(c.cart_users, 0) AS cart_users,
  COALESCE(ch.checkout_users, 0) AS checkout_users,
  COALESCE(p.purchase_users, 0) AS purchase_users,

  SAFE_DIVIDE(v.view_users, u.users) AS user_to_view_rate,
  SAFE_DIVIDE(c.cart_users, v.view_users) AS view_to_cart_rate,
  SAFE_DIVIDE(ch.checkout_users, c.cart_users) AS cart_to_checkout_rate,
  SAFE_DIVIDE(p.purchase_users, ch.checkout_users)
    AS checkout_to_purchase_rate

FROM monthly_users u
LEFT JOIN view_counts v USING (month)
LEFT JOIN cart_counts c USING (month)
LEFT JOIN checkout_counts ch USING (month)
LEFT JOIN purchase_counts p USING (month)
ORDER BY u.month;



-- =========================================================
-- 2. Add-to-cart tracking quality check
--
-- Goal:
-- Check daily view_item and add_to_cart recording.
--
-- Finding:
-- view_item remains present while add_to_cart is
-- discontinuous during parts of November.
-- =========================================================

SELECT
  event_date,
  COUNTIF(event_name = 'view_item') AS view_item_events,
  COUNTIF(event_name = 'add_to_cart') AS add_to_cart_events,

  SAFE_DIVIDE(
    COUNTIF(event_name = 'add_to_cart'),
    COUNTIF(event_name = 'view_item')
  ) AS add_to_cart_event_ratio

FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
  AND event_name IN ('view_item', 'add_to_cart')
GROUP BY event_date
ORDER BY event_date;



-- =========================================================
-- 3. Daily strict view-to-cart funnel
--
-- Output:
-- Save this query result as data/daily_funnel.csv
--
-- Goal:
-- Support daily funnel trend visualization and tracking
-- diagnostics.
--
-- Definition:
-- For each user/day, add_to_cart must occur after the
-- user's first view_item on the same day.
-- =========================================================

WITH base_events AS (
  SELECT
    event_date,
    user_pseudo_id,
    event_name,
    event_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201101' AND '20210131'
    AND event_name IN ('view_item', 'add_to_cart')
),

views AS (
  SELECT
    event_date,
    user_pseudo_id,
    MIN(event_timestamp) AS view_ts
  FROM base_events
  WHERE event_name = 'view_item'
  GROUP BY event_date, user_pseudo_id
),

carts AS (
  SELECT
    v.event_date,
    v.user_pseudo_id,
    MIN(e.event_timestamp) AS cart_ts
  FROM views v
  JOIN base_events e
    ON v.event_date = e.event_date
   AND v.user_pseudo_id = e.user_pseudo_id
   AND e.event_name = 'add_to_cart'
   AND e.event_timestamp > v.view_ts
  GROUP BY v.event_date, v.user_pseudo_id
)

SELECT
  v.event_date,
  COUNT(DISTINCT v.user_pseudo_id) AS view_users,
  COUNT(DISTINCT c.user_pseudo_id) AS cart_users,

  SAFE_DIVIDE(
    COUNT(DISTINCT c.user_pseudo_id),
    COUNT(DISTINCT v.user_pseudo_id)
  ) AS view_to_cart_rate

FROM views v
LEFT JOIN carts c
  ON v.event_date = c.event_date
 AND v.user_pseudo_id = c.user_pseudo_id
GROUP BY v.event_date
ORDER BY v.event_date;



-- =========================================================
-- 4. Weekly strict view-to-cart funnel
--
-- Output:
-- Save this query result as data/weekly_funnel.csv
--
-- Analysis window:
-- 2020-11-30 to 2021-01-31
--
-- The window starts with the first complete Monday-Sunday
-- week after add_to_cart tracking becomes relatively stable.
-- =========================================================

WITH base_events AS (
  SELECT
    DATE_TRUNC(
      PARSE_DATE('%Y%m%d', event_date),
      WEEK(MONDAY)
    ) AS week_start,
    user_pseudo_id,
    event_name,
    event_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201130' AND '20210131'
    AND event_name IN ('view_item', 'add_to_cart')
),

views AS (
  SELECT
    week_start,
    user_pseudo_id,
    MIN(event_timestamp) AS view_ts
  FROM base_events
  WHERE event_name = 'view_item'
  GROUP BY week_start, user_pseudo_id
),

carts AS (
  SELECT
    v.week_start,
    v.user_pseudo_id,
    MIN(e.event_timestamp) AS cart_ts
  FROM views v
  JOIN base_events e
    ON v.week_start = e.week_start
   AND v.user_pseudo_id = e.user_pseudo_id
   AND e.event_name = 'add_to_cart'
   AND e.event_timestamp > v.view_ts
  GROUP BY v.week_start, v.user_pseudo_id
)

SELECT
  v.week_start,
  COUNT(DISTINCT v.user_pseudo_id) AS view_users,
  COUNT(DISTINCT c.user_pseudo_id) AS cart_users,

  SAFE_DIVIDE(
    COUNT(DISTINCT c.user_pseudo_id),
    COUNT(DISTINCT v.user_pseudo_id)
  ) AS view_to_cart_rate

FROM views v
LEFT JOIN carts c
  ON v.week_start = c.week_start
 AND v.user_pseudo_id = c.user_pseudo_id
GROUP BY v.week_start
ORDER BY v.week_start;



-- =========================================================
-- 5. Before / After overall validation
--
-- Analysis split:
-- Before = weeks starting before 2020-12-14
-- After  = weeks starting on/after 2020-12-14
--
-- Each funnel is first calculated within a one-week window
-- and then aggregated so the observation window remains
-- comparable between periods.
-- =========================================================

WITH base_events AS (
  SELECT
    DATE_TRUNC(
      PARSE_DATE('%Y%m%d', event_date),
      WEEK(MONDAY)
    ) AS week_start,
    user_pseudo_id,
    event_name,
    event_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201130' AND '20210131'
    AND event_name IN ('view_item', 'add_to_cart')
),

views AS (
  SELECT
    week_start,
    user_pseudo_id,
    MIN(event_timestamp) AS view_ts
  FROM base_events
  WHERE event_name = 'view_item'
  GROUP BY week_start, user_pseudo_id
),

carts AS (
  SELECT
    v.week_start,
    v.user_pseudo_id,
    MIN(e.event_timestamp) AS cart_ts
  FROM views v
  JOIN base_events e
    ON v.week_start = e.week_start
   AND v.user_pseudo_id = e.user_pseudo_id
   AND e.event_name = 'add_to_cart'
   AND e.event_timestamp > v.view_ts
  GROUP BY v.week_start, v.user_pseudo_id
),

weekly_funnel AS (
  SELECT
    v.week_start,
    COUNT(DISTINCT v.user_pseudo_id) AS view_users,
    COUNT(DISTINCT c.user_pseudo_id) AS cart_users
  FROM views v
  LEFT JOIN carts c
    ON v.week_start = c.week_start
   AND v.user_pseudo_id = c.user_pseudo_id
  GROUP BY v.week_start
)

SELECT
  CASE
    WHEN week_start < DATE '2020-12-14' THEN 'Before'
    ELSE 'After'
  END AS period,

  SUM(view_users) AS view_users,
  SUM(cart_users) AS cart_users,

  SAFE_DIVIDE(
    SUM(cart_users),
    SUM(view_users)
  ) AS view_to_cart_rate

FROM weekly_funnel
GROUP BY period
ORDER BY
  CASE WHEN period = 'Before' THEN 1 ELSE 2 END;



-- =========================================================
-- 6. Before / After by device
--
-- Goal:
-- Test whether the decline is concentrated in one device.
--
-- The same device category is required for view and cart.
-- =========================================================

WITH base_events AS (
  SELECT
    DATE_TRUNC(
      PARSE_DATE('%Y%m%d', event_date),
      WEEK(MONDAY)
    ) AS week_start,
    user_pseudo_id,
    device.category AS device_category,
    event_name,
    event_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201130' AND '20210131'
    AND event_name IN ('view_item', 'add_to_cart')
),

views AS (
  SELECT
    week_start,
    device_category,
    user_pseudo_id,
    MIN(event_timestamp) AS view_ts
  FROM base_events
  WHERE event_name = 'view_item'
  GROUP BY week_start, device_category, user_pseudo_id
),

carts AS (
  SELECT
    v.week_start,
    v.device_category,
    v.user_pseudo_id,
    MIN(e.event_timestamp) AS cart_ts
  FROM views v
  JOIN base_events e
    ON v.week_start = e.week_start
   AND v.device_category = e.device_category
   AND v.user_pseudo_id = e.user_pseudo_id
   AND e.event_name = 'add_to_cart'
   AND e.event_timestamp > v.view_ts
  GROUP BY
    v.week_start,
    v.device_category,
    v.user_pseudo_id
),

weekly_device_funnel AS (
  SELECT
    v.week_start,
    v.device_category,
    COUNT(DISTINCT v.user_pseudo_id) AS view_users,
    COUNT(DISTINCT c.user_pseudo_id) AS cart_users
  FROM views v
  LEFT JOIN carts c
    ON v.week_start = c.week_start
   AND v.device_category = c.device_category
   AND v.user_pseudo_id = c.user_pseudo_id
  GROUP BY v.week_start, v.device_category
)

SELECT
  CASE
    WHEN week_start < DATE '2020-12-14' THEN 'Before'
    ELSE 'After'
  END AS period,

  device_category,
  SUM(view_users) AS view_users,
  SUM(cart_users) AS cart_users,

  SAFE_DIVIDE(
    SUM(cart_users),
    SUM(view_users)
  ) AS view_to_cart_rate

FROM weekly_device_funnel
GROUP BY period, device_category
ORDER BY device_category,
  CASE WHEN period = 'Before' THEN 1 ELSE 2 END;



-- =========================================================
-- 7. Before / After by acquisition source / medium
--
-- Goal:
-- Test whether the decline is concentrated in a major
-- acquisition-source group.
--
-- Note:
-- traffic_source is acquisition-source information in this
-- dataset and is not treated as current-session attribution.
-- =========================================================

WITH base_events AS (
  SELECT
    DATE_TRUNC(
      PARSE_DATE('%Y%m%d', event_date),
      WEEK(MONDAY)
    ) AS week_start,
    user_pseudo_id,
    traffic_source.source AS source,
    traffic_source.medium AS medium,
    event_name,
    event_timestamp
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE _TABLE_SUFFIX BETWEEN '20201130' AND '20210131'
    AND event_name IN ('view_item', 'add_to_cart')
),

views AS (
  SELECT
    week_start,
    source,
    medium,
    user_pseudo_id,
    MIN(event_timestamp) AS view_ts
  FROM base_events
  WHERE event_name = 'view_item'
  GROUP BY week_start, source, medium, user_pseudo_id
),

carts AS (
  SELECT
    v.week_start,
    v.source,
    v.medium,
    v.user_pseudo_id,
    MIN(e.event_timestamp) AS cart_ts
  FROM views v
  JOIN base_events e
    ON v.week_start = e.week_start
   AND v.user_pseudo_id = e.user_pseudo_id
   AND v.source IS NOT DISTINCT FROM e.source
   AND v.medium IS NOT DISTINCT FROM e.medium
   AND e.event_name = 'add_to_cart'
   AND e.event_timestamp > v.view_ts
  GROUP BY
    v.week_start,
    v.source,
    v.medium,
    v.user_pseudo_id
),

weekly_source_funnel AS (
  SELECT
    v.week_start,
    v.source,
    v.medium,
    COUNT(DISTINCT v.user_pseudo_id) AS view_users,
    COUNT(DISTINCT c.user_pseudo_id) AS cart_users
  FROM views v
  LEFT JOIN carts c
    ON v.week_start = c.week_start
   AND v.source IS NOT DISTINCT FROM c.source
   AND v.medium IS NOT DISTINCT FROM c.medium
   AND v.user_pseudo_id = c.user_pseudo_id
  GROUP BY
    v.week_start,
    v.source,
    v.medium
),

period_source AS (
  SELECT
    CASE
      WHEN week_start < DATE '2020-12-14' THEN 'Before'
      ELSE 'After'
    END AS period,
    source,
    medium,
    SUM(view_users) AS view_users,
    SUM(cart_users) AS cart_users
  FROM weekly_source_funnel
  GROUP BY period, source, medium
)

SELECT
  period,
  source,
  medium,
  view_users,
  cart_users,
  SAFE_DIVIDE(cart_users, view_users) AS view_to_cart_rate
FROM period_source
WHERE view_users >= 100
ORDER BY source, medium,
  CASE WHEN period = 'Before' THEN 1 ELSE 2 END;



-- =========================================================
-- 8. Top-product robustness summary
--
-- Goal:
-- Test whether the decline is driven by a small number of
-- major products or is broad-based across top products.
--
-- The top 20 products are selected by distinct view users
-- over the stable analysis window.
--
-- Product-level funnel requires the SAME item_id to be
-- viewed and subsequently added to cart in the same week.
-- =========================================================

WITH base_items AS (
  SELECT
    DATE_TRUNC(
      PARSE_DATE('%Y%m%d', event_date),
      WEEK(MONDAY)
    ) AS week_start,
    user_pseudo_id,
    event_name,
    event_timestamp,
    item.item_id,
    item.item_name
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`,
  UNNEST(items) AS item
  WHERE _TABLE_SUFFIX BETWEEN '20201130' AND '20210131'
    AND event_name IN ('view_item', 'add_to_cart')
),

top_products AS (
  SELECT
    item_id,
    ANY_VALUE(item_name) AS item_name,
    COUNT(DISTINCT user_pseudo_id) AS view_users
  FROM base_items
  WHERE event_name = 'view_item'
    AND item_id IS NOT NULL
    AND item_id != '(not set)'
  GROUP BY item_id
  ORDER BY view_users DESC
  LIMIT 20
),

views AS (
  SELECT
    b.week_start,
    b.item_id,
    ANY_VALUE(b.item_name) AS item_name,
    b.user_pseudo_id,
    MIN(b.event_timestamp) AS view_ts
  FROM base_items b
  JOIN top_products t
    ON b.item_id = t.item_id
  WHERE b.event_name = 'view_item'
  GROUP BY
    b.week_start,
    b.item_id,
    b.user_pseudo_id
),

carts AS (
  SELECT
    v.week_start,
    v.item_id,
    v.item_name,
    v.user_pseudo_id,
    MIN(b.event_timestamp) AS cart_ts
  FROM views v
  JOIN base_items b
    ON v.week_start = b.week_start
   AND v.item_id = b.item_id
   AND v.user_pseudo_id = b.user_pseudo_id
   AND b.event_name = 'add_to_cart'
   AND b.event_timestamp > v.view_ts
  GROUP BY
    v.week_start,
    v.item_id,
    v.item_name,
    v.user_pseudo_id
),

weekly_product_funnel AS (
  SELECT
    v.week_start,
    v.item_id,
    v.item_name,
    COUNT(DISTINCT v.user_pseudo_id) AS view_users,
    COUNT(DISTINCT c.user_pseudo_id) AS cart_users
  FROM views v
  LEFT JOIN carts c
    ON v.week_start = c.week_start
   AND v.item_id = c.item_id
   AND v.user_pseudo_id = c.user_pseudo_id
  GROUP BY
    v.week_start,
    v.item_id,
    v.item_name
),

period_product AS (
  SELECT
    CASE
      WHEN week_start < DATE '2020-12-14' THEN 'Before'
      ELSE 'After'
    END AS period,
    item_id,
    ANY_VALUE(item_name) AS item_name,
    SUM(view_users) AS view_users,
    SUM(cart_users) AS cart_users,
    SAFE_DIVIDE(
      SUM(cart_users),
      SUM(view_users)
    ) AS view_to_cart_rate
  FROM weekly_product_funnel
  GROUP BY period, item_id
),

pivoted AS (
  SELECT
    item_id,
    ANY_VALUE(item_name) AS item_name,

    MAX(
      CASE
        WHEN period = 'Before' THEN view_to_cart_rate
      END
    ) AS before_rate,

    MAX(
      CASE
        WHEN period = 'After' THEN view_to_cart_rate
      END
    ) AS after_rate

  FROM period_product
  GROUP BY item_id
),

changes AS (
  SELECT
    item_id,
    item_name,
    before_rate,
    after_rate,
    (after_rate - before_rate) * 100 AS change_pp
  FROM pivoted
  WHERE before_rate IS NOT NULL
    AND after_rate IS NOT NULL
)

SELECT
  COUNT(*) AS products_compared,
  COUNTIF(change_pp < 0) AS products_declined,

  SAFE_DIVIDE(
    COUNTIF(change_pp < 0),
    COUNT(*)
  ) * 100 AS percent_declined,

  AVG(change_pp) AS average_change_pp,

  APPROX_QUANTILES(
    change_pp,
    100
  )[OFFSET(50)] AS median_change_pp,

  MIN(change_pp) AS largest_decline_pp,
  MAX(change_pp) AS largest_increase_pp

FROM changes;



-- =========================================================
-- Final findings
-- =========================================================

-- 1. Purchase conversion deterioration is concentrated most
--    strongly at the view_item -> add_to_cart stage.
--
-- 2. November contains discontinuous add_to_cart tracking,
--    so the full-month November funnel is not interpreted as
--    directly comparable business performance.
--
-- 3. Funnel interpretation is restricted to complete weeks
--    from 2020-11-30 through 2021-01-31.
--
-- 4. Weekly strict view-to-cart conversion begins weakening
--    around mid-December and continues declining into January.
--
-- 5. Using 2020-12-14 as an analysis split, weighted
--    view-to-cart conversion declines from approximately
--    32.95% before the split to 21.16% afterward
--    (-11.8 percentage points).
--
-- 6. The decline is broad-based across device categories and
--    major acquisition source / medium groups.
--
-- 7. Among the top 20 products, 17 (85%) decline after the
--    split, with a median change of about -4.51 percentage
--    points.
--
-- 8. The observed dimensions therefore do not support a
--    single-device, single-source, or small-product-set
--    explanation.
--
-- Limitation:
-- The public dataset does not provide sufficient evidence on
-- promotions, pricing, inventory, site releases, merchandising
-- changes, or experiments. The analysis can localize and narrow
-- the problem, but cannot identify a unique causal driver.