-- Run this once in the Supabase SQL Editor.
-- Creates a function that upserts a JSON batch into scrape_data with a
-- 120-second statement timeout — overrides the service_role default (8s).
--
-- Dropped columns (no longer in scrape_data):
--   model_code, views_gained, datetrackinglink, thumbnail,
--   curr_vert, curr_user, curr_model, curr_tm
-- caption is kept.

CREATE OR REPLACE FUNCTION upsert_scrape_batch(batch jsonb)
RETURNS void
LANGUAGE plpgsql
SET statement_timeout = '120s'
AS $$
BEGIN
  INSERT INTO scrape_data (
    row_key, post_url, post_id, post_timestamp, content_type, caption,
    verticals, comments, likes, views, scrape_date, username,
    model_stage_name, x_score, followers, employee,
    tracking_link, acc_no, trial, is_shared_to_feed,
    user_id, talent_manager, team
  )
  SELECT
    r.row_key,
    r.post_url,
    r.post_id,
    (r.post_timestamp)::date,
    r.content_type,
    r.caption,
    r.verticals,
    (r.comments)::float8,
    (r.likes)::float8,
    (r.views)::float8,
    (r.scrape_date)::date,
    r.username,
    r.model_stage_name,
    (r.x_score)::float8,
    (r.followers)::float8,
    r.employee,
    r.tracking_link,
    (r.acc_no)::bigint,
    r.trial,
    (r.is_shared_to_feed)::boolean,
    (r.user_id)::bigint,
    r.talent_manager,
    r.team
  FROM jsonb_to_recordset(batch) AS r(
    row_key          text,
    post_url         text,
    post_id          text,
    post_timestamp   text,
    content_type     text,
    caption          text,
    verticals        text,
    comments         float8,
    likes            float8,
    views            float8,
    scrape_date      text,
    username         text,
    model_stage_name text,
    x_score          float8,
    followers        float8,
    employee         text,
    tracking_link    text,
    acc_no           bigint,
    trial            text,
    is_shared_to_feed boolean,
    user_id          bigint,
    talent_manager   text,
    team             text
  )
  ON CONFLICT (row_key) DO UPDATE SET
    post_url          = EXCLUDED.post_url,
    post_id           = EXCLUDED.post_id,
    post_timestamp    = EXCLUDED.post_timestamp,
    content_type      = EXCLUDED.content_type,
    caption           = EXCLUDED.caption,
    verticals         = EXCLUDED.verticals,
    comments          = EXCLUDED.comments,
    likes             = EXCLUDED.likes,
    views             = EXCLUDED.views,
    scrape_date       = EXCLUDED.scrape_date,
    username          = EXCLUDED.username,
    model_stage_name  = EXCLUDED.model_stage_name,
    x_score           = EXCLUDED.x_score,
    followers         = EXCLUDED.followers,
    employee          = EXCLUDED.employee,
    tracking_link     = EXCLUDED.tracking_link,
    acc_no            = EXCLUDED.acc_no,
    trial             = EXCLUDED.trial,
    is_shared_to_feed = EXCLUDED.is_shared_to_feed,
    user_id           = EXCLUDED.user_id,
    talent_manager    = EXCLUDED.talent_manager,
    team              = EXCLUDED.team;
END;
$$;
