-- ============================================================
-- EMF Instagram Tracking - Supabase Schema (flat table)
-- Run this in the Supabase SQL editor
-- ============================================================

-- ============================================================
-- DROP OLD OBJECTS (safe to re-run)
-- ============================================================

DROP VIEW IF EXISTS v_winner_stats_account    CASCADE;
DROP VIEW IF EXISTS v_winner_stats_model      CASCADE;
DROP VIEW IF EXISTS v_views_timeline          CASCADE;
DROP VIEW IF EXISTS v_top_reels               CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_account_median CASCADE;
DROP VIEW IF EXISTS v_account_median          CASCADE;
DROP MATERIALIZED VIEW IF EXISTS mv_post_latest    CASCADE;
DROP VIEW IF EXISTS v_post_latest             CASCADE;

DROP TABLE IF EXISTS post_scrapes CASCADE;
DROP TABLE IF EXISTS posts         CASCADE;
DROP TABLE IF EXISTS accounts      CASCADE;
DROP TABLE IF EXISTS models        CASCADE;
DROP TABLE IF EXISTS scrape_data   CASCADE;

-- ============================================================
-- FLAT TABLE  (mirrors the xlsx sheet columns exactly)
-- ============================================================

CREATE TABLE scrape_data (
  id                UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  row_key           TEXT        NOT NULL UNIQUE,  -- stable upsert key (see import script)

  -- Sheet columns (same names, lowercased + underscored)
  post_url          TEXT,
  post_id           TEXT,                          -- Instagram numeric post ID
  post_timestamp    DATE,                          -- "Pool Date"
  content_type      TEXT,
  caption           TEXT,
  verticals         TEXT,                          -- comma-separated string
  comments          NUMERIC,
  likes             NUMERIC,
  views             NUMERIC     DEFAULT 0,
  scrape_date       DATE,
  username          TEXT,
  model_code        TEXT,
  model_stage_name  TEXT,
  x_score           NUMERIC,
  followers         NUMERIC,
  employee          TEXT,
  tracking_link     TEXT,
  acc_no            SMALLINT,
  trial             TEXT,                          -- 'Normal Reel', 'Trial Reel', NULL
  views_gained      NUMERIC     DEFAULT 0,
  datetrackinglink  TEXT,
  thumbnail         TEXT,
  is_shared_to_feed BOOLEAN,
  curr_vert         TEXT,
  user_id           BIGINT,
  talent_manager    TEXT,
  curr_user         TEXT,
  curr_model        TEXT,
  curr_tm           TEXT,
  team              TEXT,

  -- Operational column (not in sheet — used by the n8n automation)
  transferred       BOOLEAN     DEFAULT FALSE,

  created_at        TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- INDEXES
-- ============================================================

-- Primary lookup / upsert
CREATE INDEX idx_scrape_data_post_id      ON scrape_data (post_id)      WHERE post_id IS NOT NULL;
CREATE INDEX idx_scrape_data_scrape_date  ON scrape_data (scrape_date);
CREATE INDEX idx_scrape_data_username     ON scrape_data (username);
CREATE INDEX idx_scrape_data_transferred  ON scrape_data (transferred)  WHERE transferred = FALSE;

-- Composite index for DISTINCT ON (post_id) ORDER BY post_id, scrape_date DESC
CREATE INDEX idx_scrape_data_post_scrape  ON scrape_data (post_id, scrape_date DESC) WHERE post_id IS NOT NULL;

-- Timeline query: fetch all scrape rows for a set of post_ids filtered by scrape_date
CREATE INDEX idx_scrape_data_timeline     ON scrape_data (post_id, scrape_date) WHERE post_id IS NOT NULL AND scrape_date IS NOT NULL;

-- Dashboard date-range filter
CREATE INDEX idx_scrape_data_post_ts      ON scrape_data (post_timestamp) WHERE post_timestamp IS NOT NULL;

-- ============================================================
-- MATERIALIZED VIEWS
-- Both are refreshed by the import script after each run.
-- Manual refresh: SELECT refresh_materialized_views();
-- ============================================================

-- mv_post_latest: most recent scrape row per post, pre-computed.
-- Replaces the live DISTINCT ON view that had to scan all 200k+ rows on every query.
CREATE MATERIALIZED VIEW mv_post_latest AS
SELECT DISTINCT ON (post_id)
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
  model_code,
  model_stage_name,
  x_score,
  followers,
  employee,
  tracking_link,
  acc_no,
  trial,
  views_gained,
  datetrackinglink,
  thumbnail,
  is_shared_to_feed,
  curr_vert,
  user_id,
  talent_manager,
  curr_user,
  curr_model,
  curr_tm,
  team,
  transferred
FROM scrape_data
WHERE post_id IS NOT NULL
ORDER BY post_id, scrape_date DESC;

-- Indexes on mv_post_latest for fast dashboard filtering
CREATE UNIQUE INDEX idx_mv_post_latest_post_id    ON mv_post_latest (post_id);
CREATE INDEX idx_mv_post_latest_username          ON mv_post_latest (username);
CREATE INDEX idx_mv_post_latest_post_ts           ON mv_post_latest (post_timestamp);
CREATE INDEX idx_mv_post_latest_views             ON mv_post_latest (views DESC);
CREATE INDEX idx_mv_post_latest_model             ON mv_post_latest (model_stage_name);
CREATE INDEX idx_mv_post_latest_team              ON mv_post_latest (team);
CREATE INDEX idx_mv_post_latest_talent_mgr        ON mv_post_latest (talent_manager);
CREATE INDEX idx_mv_post_latest_curr_tm           ON mv_post_latest (curr_tm);
CREATE INDEX idx_mv_post_latest_transferred       ON mv_post_latest (transferred) WHERE transferred = FALSE;


-- mv_account_median: median views per account — pre-computed so PERCENTILE_CONT
-- is not recalculated on every dashboard query.
CREATE MATERIALIZED VIEW mv_account_median AS
SELECT
  username,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY views) AS median_views
FROM mv_post_latest
GROUP BY username;

CREATE UNIQUE INDEX idx_mv_account_median_username ON mv_account_median (username);


-- ============================================================
-- VIEWS (thin aliases over the materialized views)
-- ============================================================

-- v_filter_options: distinct QM/TM/team/vertical combos for active models only.
-- Returns at most a few hundred rows — safe from Supabase's default row cap.
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
  pl.curr_tm           AS tm,
  pl.team,
  pl.curr_vert
FROM mv_post_latest pl
JOIN model_config mc ON mc.model_name = pl.model_stage_name
WHERE mc.is_active = TRUE;

-- v_post_latest: alias kept for n8n automation compatibility
CREATE OR REPLACE VIEW v_post_latest AS
SELECT * FROM mv_post_latest;

-- v_account_median: alias kept for backwards compatibility
CREATE OR REPLACE VIEW v_account_median AS
SELECT username, median_views FROM mv_account_median;


-- v_top_reels: fully denormalized — used by the n8n automation and dashboard
-- Filters: post_timestamp, model_stage_name, username, team, talent_manager, curr_tm, verticals
-- Note for n8n: PATCH scrape_data?post_id=eq.{post_id} to set transferred=true
CREATE OR REPLACE VIEW v_top_reels AS
SELECT
  pl.id                                                   AS row_id,
  pl.post_id,                                             -- IG post ID (use for PATCH)
  pl.post_url,
  pl.post_timestamp,
  pl.content_type,
  pl.caption,
  pl.curr_vert,
  regexp_split_to_array(pl.curr_vert, '\s*,\s*')         AS verticals_array,
  pl.verticals,
  pl.thumbnail,
  pl.trial                                                AS trial_type,
  pl.transferred,
  pl.username,
  pl.acc_no,
  pl.employee                                             AS owner,
  pl.talent_manager,
  pl.curr_tm                                              AS tm,
  pl.user_id,
  pl.tracking_link,
  pl.model_stage_name                                     AS model,
  pl.model_code,
  pl.team,
  pl.views,
  pl.likes,
  pl.comments,
  pl.followers,
  pl.x_score,
  pl.scrape_date,
  pl.views_gained,
  am.median_views,
  CASE
    WHEN am.median_views > 0
    THEN ROUND((pl.views / am.median_views)::NUMERIC, 2)
    ELSE NULL
  END                                                     AS multiplier_score,
  (pl.views >= 100000)                                    AS is_winner,
  (
    (pl.views >= 100000)
    OR (
      am.median_views > 0
      AND (pl.views / am.median_views) >= 2.5
    )
  )                                                       AS met_multiplier,
  pl.curr_user,
  pl.curr_model,
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
  END                                                     AS qm
FROM mv_post_latest pl
JOIN mv_account_median am ON am.username = pl.username;


-- v_views_timeline: one row per post × scrape_date so the dashboard can
-- chart view-count growth across scrape dates for each post.
CREATE OR REPLACE VIEW v_views_timeline AS
SELECT
  sd.scrape_date,
  sd.post_timestamp                                       AS post_date,
  sd.post_id,
  sd.post_url,
  sd.username,
  sd.model_stage_name                                     AS model,
  sd.team,
  sd.talent_manager                                       AS qm,
  sd.curr_tm                                              AS tm,
  sd.views
FROM scrape_data sd
WHERE sd.post_id      IS NOT NULL
  AND sd.scrape_date  IS NOT NULL
  AND sd.post_timestamp IS NOT NULL
ORDER BY sd.post_timestamp, sd.scrape_date, sd.username;


-- v_winner_stats_model: winner count and rate by model
CREATE OR REPLACE VIEW v_winner_stats_model AS
SELECT
  pl.model_stage_name                                     AS model,
  pl.team,
  COUNT(*)                                                AS total_posts,
  COUNT(*) FILTER (WHERE pl.views >= 100000)              AS winner_count,
  ROUND(
    COUNT(*) FILTER (WHERE pl.views >= 100000)::NUMERIC
    / NULLIF(COUNT(*), 0) * 100, 2
  )                                                       AS winner_rate_pct
FROM mv_post_latest pl
GROUP BY pl.model_stage_name, pl.team
ORDER BY winner_count DESC;


-- v_winner_stats_account: winner count and rate by account
CREATE OR REPLACE VIEW v_winner_stats_account AS
SELECT
  pl.username,
  pl.acc_no,
  pl.model_stage_name                                     AS model,
  pl.team,
  pl.employee                                             AS owner,
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
  END                                                     AS qm,
  pl.curr_tm                                              AS tm,
  COUNT(*)                                                AS total_posts,
  COUNT(*) FILTER (WHERE pl.views >= 100000)              AS winner_count,
  ROUND(
    COUNT(*) FILTER (WHERE pl.views >= 100000)::NUMERIC
    / NULLIF(COUNT(*), 0) * 100, 2
  )                                                       AS winner_rate_pct
FROM mv_post_latest pl
GROUP BY pl.username, pl.acc_no, pl.model_stage_name, pl.team,
         pl.employee, pl.curr_tm
ORDER BY winner_count DESC;


-- ============================================================
-- RPC: refresh_materialized_views
-- Refreshes mv_post_latest then mv_account_median (order matters).
-- Called by import_xlsx.py after each import run via supabase.rpc().
-- Requires service_role key — the anon key cannot execute this.
-- SET LOCAL raises the timeout for this transaction only.
-- ============================================================

CREATE OR REPLACE FUNCTION refresh_materialized_views()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET LOCAL statement_timeout = '600s';
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_post_latest;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_account_median;
END;
$$;


-- ============================================================
-- TRIGGER: auto-refresh materialized views on scrape_data changes
-- Fires once per statement (not per row) to avoid redundant refreshes
-- during bulk imports. CONCURRENTLY requires the unique indexes above.
-- ============================================================

CREATE OR REPLACE FUNCTION trigger_refresh_materialized_views()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  SET LOCAL statement_timeout = '600s';
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_post_latest;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_account_median;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE TRIGGER trg_refresh_mv_after_scrape_data
AFTER INSERT OR UPDATE OR DELETE ON scrape_data
FOR EACH STATEMENT
EXECUTE FUNCTION trigger_refresh_materialized_views();


-- ============================================================
-- RPC: get_winner_stats
-- Returns winner count and rate aggregated by model and account,
-- with all dashboard filters applied server-side. Returns one row
-- per model and one row per account — no row-cap risk.
-- Called by the dashboard fetchWinnerStats() instead of querying
-- the pre-aggregated views directly.
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
    WHERE (p_date_from      IS NULL OR pl.post_timestamp >= p_date_from)
      AND (p_date_to        IS NULL OR pl.post_timestamp <= p_date_to)
      AND (p_model          IS NULL OR pl.model_stage_name = p_model)
      AND (p_username       IS NULL OR pl.username = p_username)
      AND (p_team           IS NULL OR pl.team = p_team)
      AND (p_tm             IS NULL OR pl.curr_tm = p_tm)
      AND (p_vertical       IS NULL OR pl.curr_vert ILIKE '%' || p_vertical || '%')
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
-- ROW LEVEL SECURITY (optional — enable when ready)
-- ============================================================
-- ALTER TABLE scrape_data ENABLE ROW LEVEL SECURITY;
-- CREATE POLICY "public read" ON scrape_data FOR SELECT USING (true);
