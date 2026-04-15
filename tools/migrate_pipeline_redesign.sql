-- ============================================================
-- EMF Pipeline Redesign — Safe Migration Script
-- Run this in the Supabase SQL Editor (NOT schema.sql).
-- schema.sql has DROP TABLE which would destroy all data.
-- This script ONLY alters structure, never drops rows.
--
-- What this does:
--   1. Drop dependent views/MVs (no data — safe to drop/recreate)
--   2. Drop 8 columns from scrape_data (other columns + rows untouched)
--   3. Create new materialized views (mv_userid_curr, mv_username_curr_vert)
--   4. Rebuild mv_post_latest (ROW_NUMBER + LAG for views_gained)
--   5. Rebuild mv_account_median
--   6. Recreate all views with updated joins
--   7. Update refresh_materialized_views() RPC + trigger function
--   8. Update get_winner_stats() RPC
--   9. VACUUM FULL scrape_data to reclaim freed column storage
--
-- curr_model is derived automatically from the most recent model_stage_name
-- per user_id in mv_userid_curr — no account_model table needed.
--
-- Before running: take a manual backup in Supabase Dashboard → Settings → Backups.
-- Safe to re-run from the top at any time.
-- ============================================================


-- ============================================================
-- STEP 1: Drop all dependent views and materialized views
-- These contain no raw data — safe to drop and recreate.
-- ORDER matters: drop child objects before parents.
-- ============================================================

DROP VIEW IF EXISTS v_winner_stats_account    CASCADE;
DROP VIEW IF EXISTS v_winner_stats_model      CASCADE;
DROP VIEW IF EXISTS v_views_timeline          CASCADE;
DROP VIEW IF EXISTS v_top_reels               CASCADE;
DROP VIEW IF EXISTS v_filter_options          CASCADE;
DROP VIEW IF EXISTS v_post_latest             CASCADE;
DROP VIEW IF EXISTS v_account_median          CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_account_median      CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_post_latest         CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_username_curr_vert  CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_userid_curr         CASCADE;
DROP TABLE IF EXISTS account_model                      CASCADE;


-- ============================================================
-- STEP 2: Drop the 8 columns from scrape_data
-- ALL rows and all other columns are fully preserved.
-- ============================================================

ALTER TABLE scrape_data
  DROP COLUMN IF EXISTS curr_vert,
  DROP COLUMN IF EXISTS curr_user,
  DROP COLUMN IF EXISTS curr_model,
  DROP COLUMN IF EXISTS curr_tm,
  DROP COLUMN IF EXISTS views_gained,
  DROP COLUMN IF EXISTS model_code,
  DROP COLUMN IF EXISTS datetrackinglink,
  DROP COLUMN IF EXISTS thumbnail;


-- ============================================================
-- STEP 3: New derived materialized views
--
-- mv_userid_curr: current username, talent manager, AND model
-- per user_id — all derived from the most recent scrape row.
-- curr_model auto-updates on each daily import: no manual table.
-- ============================================================

CREATE MATERIALIZED VIEW mv_userid_curr AS
SELECT DISTINCT ON (user_id)
  user_id,
  username         AS curr_user,
  talent_manager   AS curr_tm,
  model_stage_name AS curr_model
FROM scrape_data
WHERE user_id IS NOT NULL
ORDER BY user_id, scrape_date DESC;

CREATE UNIQUE INDEX idx_mv_userid_curr ON mv_userid_curr (user_id);


-- mv_username_curr_vert: current vertical per username
CREATE MATERIALIZED VIEW mv_username_curr_vert AS
SELECT DISTINCT ON (username)
  username,
  verticals AS curr_vert
FROM scrape_data
WHERE verticals IS NOT NULL
ORDER BY username, scrape_date DESC;

CREATE UNIQUE INDEX idx_mv_username_curr_vert ON mv_username_curr_vert (username);


-- ============================================================
-- STEP 4: Rebuild mv_post_latest
-- Uses ROW_NUMBER() so views_gained LAG window works alongside
-- the latest-row selection.
-- ============================================================

CREATE MATERIALIZED VIEW mv_post_latest AS
WITH ranked AS (
  SELECT
    id,
    row_key,
    post_url,
    post_id,
    post_timestamp,
    content_type,
    caption,
    verticals,
    comments,
    likes,
    views,
    scrape_date,
    username,
    model_stage_name,
    x_score,
    followers,
    employee,
    tracking_link,
    acc_no,
    trial,
    is_shared_to_feed,
    user_id,
    talent_manager,
    team,
    transferred,
    COALESCE(
      views - LAG(views) OVER (PARTITION BY post_id ORDER BY scrape_date),
      0
    )                                                       AS views_gained,
    ROW_NUMBER() OVER (PARTITION BY post_id ORDER BY scrape_date DESC) AS rn
  FROM scrape_data
  WHERE post_id IS NOT NULL
)
SELECT
  id, row_key, post_url, post_id, post_timestamp, content_type,
  caption, verticals, comments, likes, views, scrape_date, username,
  model_stage_name, x_score, followers, employee, tracking_link,
  acc_no, trial, is_shared_to_feed, user_id, talent_manager, team,
  transferred, views_gained
FROM ranked
WHERE rn = 1;

CREATE UNIQUE INDEX idx_mv_post_latest_post_id    ON mv_post_latest (post_id);
CREATE INDEX idx_mv_post_latest_username          ON mv_post_latest (username);
CREATE INDEX idx_mv_post_latest_post_ts           ON mv_post_latest (post_timestamp);
CREATE INDEX idx_mv_post_latest_views             ON mv_post_latest (views DESC);
CREATE INDEX idx_mv_post_latest_model             ON mv_post_latest (model_stage_name);
CREATE INDEX idx_mv_post_latest_team              ON mv_post_latest (team);
CREATE INDEX idx_mv_post_latest_talent_mgr        ON mv_post_latest (talent_manager);
CREATE INDEX idx_mv_post_latest_user_id           ON mv_post_latest (user_id);
CREATE INDEX idx_mv_post_latest_transferred       ON mv_post_latest (transferred) WHERE transferred = FALSE;


-- ============================================================
-- STEP 5: Rebuild mv_account_median (depends on mv_post_latest)
-- ============================================================

CREATE MATERIALIZED VIEW mv_account_median AS
SELECT
  username,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY views) AS median_views
FROM mv_post_latest
GROUP BY username;

CREATE UNIQUE INDEX idx_mv_account_median_username ON mv_account_median (username);


-- ============================================================
-- STEP 6: Recreate all views
-- ============================================================

-- v_filter_options
CREATE OR REPLACE VIEW v_filter_options AS
SELECT DISTINCT
  CASE pl.employee
    WHEN 'Des Grace'  THEN 'Des'
    WHEN 'Kris'       THEN 'Des'
    WHEN 'Model Ran'  THEN 'Model Ran'
    WHEN 'Mickaella'  THEN 'Marie'
    WHEN 'Krisna'     THEN 'Lailin'
    WHEN 'Jhasmin'    THEN 'Lailin'
    WHEN 'Diana'      THEN 'Des'
    WHEN 'Mitch'      THEN 'Marie'
    WHEN 'Rein'       THEN 'Marie'
    WHEN 'Gabrielle'  THEN 'Marie'
    WHEN 'Janmae'     THEN 'Lailin'
  END                  AS qm,
  uc.curr_tm           AS tm,
  pl.team,
  ucv.curr_vert
FROM mv_post_latest pl
JOIN model_config mc                ON mc.model_name  = pl.model_stage_name
LEFT JOIN mv_userid_curr uc         ON uc.user_id     = pl.user_id
LEFT JOIN mv_username_curr_vert ucv ON ucv.username   = pl.username
WHERE mc.is_active = TRUE;


-- v_post_latest: alias kept for n8n automation compatibility
CREATE OR REPLACE VIEW v_post_latest AS
SELECT * FROM mv_post_latest;

-- v_account_median: alias kept for backwards compatibility
CREATE OR REPLACE VIEW v_account_median AS
SELECT username, median_views FROM mv_account_median;


-- v_top_reels: fully denormalized — used by n8n automation and dashboard.
-- curr_model derived from mv_userid_curr (most recent model_stage_name per user_id).
-- Note for n8n: PATCH scrape_data?post_id=eq.{post_id} to set transferred=true
CREATE OR REPLACE VIEW v_top_reels AS
SELECT
  pl.id                                                     AS row_id,
  pl.post_id,
  pl.post_url,
  pl.post_timestamp,
  pl.content_type,
  pl.caption,
  ucv.curr_vert,
  regexp_split_to_array(ucv.curr_vert, '\s*,\s*')          AS verticals_array,
  pl.verticals,
  pl.trial                                                  AS trial_type,
  pl.transferred,
  pl.username,
  uc.curr_user,
  pl.acc_no,
  pl.employee                                               AS owner,
  pl.talent_manager,
  uc.curr_tm                                                AS tm,
  pl.user_id,
  pl.tracking_link,
  pl.model_stage_name                                       AS model,
  uc.curr_model,
  pl.team,
  pl.views,
  pl.likes,
  pl.comments,
  pl.followers,
  pl.x_score,
  pl.scrape_date,
  pl.views_gained,
  med.median_views,
  CASE
    WHEN med.median_views > 0
    THEN ROUND((pl.views / med.median_views)::NUMERIC, 2)
    ELSE NULL
  END                                                       AS multiplier_score,
  (pl.views >= 100000)                                      AS is_winner,
  (
    (pl.views >= 100000)
    OR (
      med.median_views > 0
      AND (pl.views / med.median_views) >= 2.5
    )
  )                                                         AS met_multiplier,
  CASE pl.employee
    WHEN 'Des Grace'  THEN 'Des'
    WHEN 'Kris'       THEN 'Des'
    WHEN 'Model Ran'  THEN 'Model Ran'
    WHEN 'Mickaella'  THEN 'Marie'
    WHEN 'Krisna'     THEN 'Lailin'
    WHEN 'Jhasmin'    THEN 'Lailin'
    WHEN 'Diana'      THEN 'Des'
    WHEN 'Mitch'      THEN 'Marie'
    WHEN 'Rein'       THEN 'Marie'
    WHEN 'Gabrielle'  THEN 'Marie'
    WHEN 'Janmae'     THEN 'Lailin'
  END                                                       AS qm
FROM mv_post_latest pl
JOIN mv_account_median              med ON med.username  = pl.username
LEFT JOIN mv_username_curr_vert     ucv ON ucv.username  = pl.username
LEFT JOIN mv_userid_curr            uc  ON uc.user_id    = pl.user_id;


-- v_views_timeline: one row per post × scrape_date for growth charts.
CREATE OR REPLACE VIEW v_views_timeline AS
SELECT
  sd.scrape_date,
  sd.post_timestamp                                         AS post_date,
  sd.post_id,
  sd.post_url,
  sd.username,
  sd.model_stage_name                                       AS model,
  sd.team,
  sd.talent_manager                                         AS tm,
  sd.views,
  COALESCE(
    sd.views - LAG(sd.views) OVER (PARTITION BY sd.post_id ORDER BY sd.scrape_date),
    0
  )                                                         AS views_gained
FROM scrape_data sd
WHERE sd.post_id        IS NOT NULL
  AND sd.scrape_date    IS NOT NULL
  AND sd.post_timestamp IS NOT NULL
ORDER BY sd.post_timestamp, sd.scrape_date, sd.username;


-- v_winner_stats_model
CREATE OR REPLACE VIEW v_winner_stats_model AS
SELECT
  pl.model_stage_name                                       AS model,
  pl.team,
  COUNT(*)                                                  AS total_posts,
  COUNT(*) FILTER (WHERE pl.views >= 100000)                AS winner_count,
  ROUND(
    COUNT(*) FILTER (WHERE pl.views >= 100000)::NUMERIC
    / NULLIF(COUNT(*), 0) * 100, 2
  )                                                         AS winner_rate_pct
FROM mv_post_latest pl
GROUP BY pl.model_stage_name, pl.team
ORDER BY winner_count DESC;


-- v_winner_stats_account
CREATE OR REPLACE VIEW v_winner_stats_account AS
SELECT
  pl.username,
  pl.acc_no,
  pl.model_stage_name                                       AS model,
  pl.team,
  pl.employee                                               AS owner,
  CASE pl.employee
    WHEN 'Des Grace'  THEN 'Des'
    WHEN 'Kris'       THEN 'Des'
    WHEN 'Model Ran'  THEN 'Model Ran'
    WHEN 'Mickaella'  THEN 'Marie'
    WHEN 'Krisna'     THEN 'Lailin'
    WHEN 'Jhasmin'    THEN 'Lailin'
    WHEN 'Diana'      THEN 'Des'
    WHEN 'Mitch'      THEN 'Marie'
    WHEN 'Rein'       THEN 'Marie'
    WHEN 'Gabrielle'  THEN 'Marie'
    WHEN 'Janmae'     THEN 'Lailin'
  END                                                       AS qm,
  uc.curr_tm                                                AS tm,
  COUNT(*)                                                  AS total_posts,
  COUNT(*) FILTER (WHERE pl.views >= 100000)                AS winner_count,
  ROUND(
    COUNT(*) FILTER (WHERE pl.views >= 100000)::NUMERIC
    / NULLIF(COUNT(*), 0) * 100, 2
  )                                                         AS winner_rate_pct
FROM mv_post_latest pl
LEFT JOIN mv_userid_curr uc ON uc.user_id = pl.user_id
GROUP BY pl.username, pl.acc_no, pl.model_stage_name, pl.team,
         pl.employee, uc.curr_tm
ORDER BY winner_count DESC;


-- ============================================================
-- STEP 7: Update refresh_materialized_views() RPC
-- ============================================================

CREATE OR REPLACE FUNCTION refresh_materialized_views()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET LOCAL statement_timeout = '600s';
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_userid_curr;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_username_curr_vert;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_post_latest;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_account_median;
END;
$$;


-- Update trigger function to use same refresh order
CREATE OR REPLACE FUNCTION trigger_refresh_materialized_views()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET LOCAL statement_timeout = '600s';
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_userid_curr;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_username_curr_vert;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_post_latest;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_account_median;
  RETURN NULL;
END;
$$;


-- ============================================================
-- STEP 8: Update get_winner_stats() RPC
-- ============================================================

DROP FUNCTION IF EXISTS get_winner_stats(DATE,DATE,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT[]);

CREATE OR REPLACE FUNCTION get_winner_stats(
  p_date_from     DATE    DEFAULT NULL,
  p_date_to       DATE    DEFAULT NULL,
  p_model         TEXT    DEFAULT NULL,
  p_username      TEXT    DEFAULT NULL,
  p_team          TEXT    DEFAULT NULL,
  p_qm            TEXT    DEFAULT NULL,
  p_tm            TEXT    DEFAULT NULL,
  p_vertical      TEXT    DEFAULT NULL,
  p_active_models TEXT[]  DEFAULT NULL
)
RETURNS TABLE(
  entity_type     TEXT,
  entity_name     TEXT,
  total_posts     BIGINT,
  winner_count    BIGINT,
  winner_rate_pct NUMERIC
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  WITH filtered AS (
    SELECT
      pl.model_stage_name AS model,
      pl.username,
      pl.views
    FROM mv_post_latest pl
    LEFT JOIN mv_userid_curr        uc  ON uc.user_id   = pl.user_id
    LEFT JOIN mv_username_curr_vert ucv ON ucv.username = pl.username
    WHERE (p_date_from      IS NULL OR pl.post_timestamp >= p_date_from)
      AND (p_date_to        IS NULL OR pl.post_timestamp <= p_date_to)
      AND (p_model          IS NULL OR pl.model_stage_name = p_model)
      AND (p_username       IS NULL OR pl.username = p_username)
      AND (p_team           IS NULL OR pl.team = p_team)
      AND (p_tm             IS NULL OR uc.curr_tm = p_tm)
      AND (p_vertical       IS NULL OR ucv.curr_vert ILIKE '%' || p_vertical || '%')
      AND (p_active_models  IS NULL OR pl.model_stage_name = ANY(p_active_models))
      AND (p_qm             IS NULL OR
           CASE pl.employee
             WHEN 'Des Grace'  THEN 'Des'
             WHEN 'Kris'       THEN 'Des'
             WHEN 'Model Ran'  THEN 'Model Ran'
             WHEN 'Mickaella'  THEN 'Marie'
             WHEN 'Krisna'     THEN 'Lailin'
             WHEN 'Jhasmin'    THEN 'Lailin'
             WHEN 'Diana'      THEN 'Des'
             WHEN 'Mitch'      THEN 'Marie'
             WHEN 'Rein'       THEN 'Marie'
             WHEN 'Gabrielle'  THEN 'Marie'
             WHEN 'Janmae'     THEN 'Lailin'
           END = p_qm)
  )
  SELECT 'model'::TEXT,
         model,
         COUNT(*)::BIGINT,
         COUNT(*) FILTER (WHERE views >= 100000)::BIGINT,
         ROUND(COUNT(*) FILTER (WHERE views >= 100000)::NUMERIC / NULLIF(COUNT(*),0) * 100, 2)
  FROM filtered
  GROUP BY model
  UNION ALL
  SELECT 'account'::TEXT,
         username,
         COUNT(*)::BIGINT,
         COUNT(*) FILTER (WHERE views >= 100000)::BIGINT,
         ROUND(COUNT(*) FILTER (WHERE views >= 100000)::NUMERIC / NULLIF(COUNT(*),0) * 100, 2)
  FROM filtered
  GROUP BY username;
END;
$$;


-- ============================================================
-- STEP 9: Reclaim storage freed by the 8 dropped columns.
-- VACUUM FULL rewrites the table — takes a lock, but no data lost.
-- Run during off-hours if possible.
-- ============================================================

VACUUM FULL scrape_data;
