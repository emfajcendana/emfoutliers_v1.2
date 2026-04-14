# Workflow: Dashboard Setup

## Objective
Stand up the Supabase database and connect the Winners Identifier dashboard.

## Step 1 — Create Supabase Project
1. Go to [supabase.com](https://supabase.com) → New Project
2. Note your **Project URL** and **anon public key** (Settings → API)
3. Add to `.env`:
   ```
   SUPABASE_URL=https://xxxx.supabase.co
   SUPABASE_ANON_KEY=eyJ...
   ```

## Step 2 — Run Schema
1. Open the Supabase SQL editor
2. Paste and run the full contents of `tools/schema.sql`
3. Verify: Tables tab should show `models`, `accounts`, `posts`, `post_scrapes`
4. Verify: Views tab should show `v_top_reels`, `v_views_timeline`, `v_winner_stats_model`, `v_winner_stats_account`, `v_post_latest`, `v_account_median`

## Step 3 — Configure Dashboard
1. Open `dashboard/index.html`
2. Replace at the top of the file:
   ```js
   const SUPABASE_URL  = 'https://xxxx.supabase.co';
   const SUPABASE_ANON = 'eyJ...your anon key...';
   ```

## Step 4 — Load Data

**Install dependencies (one time):**
```bash
pip install openpyxl supabase python-dotenv
```

**Run the import:**
```bash
python tools/import_xlsx.py ".tmp/EMF_IG Tracking MEDIAN.xlsx"
```

Output looks like:
```
── Reading .tmp/EMF_IG Tracking MEDIAN.xlsx
   111 data rows found

✓ models:       4 upserted
✓ accounts:     4 upserted
✓ posts:        109 upserted
✓ post_scrapes: 109 upserted

── Import complete.
```

**Fully idempotent** — re-running on the same or updated file is always safe. Existing rows are updated, new rows are inserted, nothing is deleted.

**Manual test insert (SQL editor):**
```sql
INSERT INTO models (stage_name, model_code, team) VALUES
  ('Judy', 'Judy 4', NULL),
  ('Candace', 'Candace 3', NULL);

INSERT INTO accounts (username, user_id, acc_no, model_id, employee, qm, tm) VALUES
  ('missjudyblack', 78175697003, 4,
   (SELECT id FROM models WHERE stage_name = 'Judy'),
   'Diana', 'Sofia Chavez', 'Sofia Chavez'),
  ('candaceestorm_ca', NULL, 3,
   (SELECT id FROM models WHERE stage_name = 'Candace'),
   'Krisna', 'Sofia Chavez', NULL);
```

## Step 5 — Open Dashboard
Open `dashboard/index.html` in a browser. No server needed — it runs fully client-side.

## Data Schema Reference

| Table | Purpose |
|---|---|
| `models` | Talent/performers (Judy, Candace, etc.) |
| `accounts` | Instagram accounts linked to models |
| `posts` | One row per unique IG post (static metadata) |
| `post_scrapes` | One row per scrape event — tracks views/likes over time |

| View | Used by |
|---|---|
| `v_post_latest` | Internal — latest scrape per post |
| `v_account_median` | Internal — per-account median views |
| `v_top_reels` | Top Reels table + all filters |
| `v_views_timeline` | Views Timeline chart |
| `v_winner_stats_model` | Winner count/rate charts by model |
| `v_winner_stats_account` | Winner count/rate charts by account |

## Field Mapping (Spreadsheet → Database)

| Spreadsheet | Database | Dashboard label |
|---|---|---|
| Model Stage Name | `models.stage_name` | Model |
| Username | `accounts.username` | Username |
| Acc No | `accounts.acc_no` | Acc |
| Post timestamp | `posts.post_timestamp` | Pool Date |
| Employee | `accounts.employee` | Owner |
| Talent Manager | `accounts.qm` | QM |
| Curr TM | `accounts.tm` | TM |
| Views | `post_scrapes.views` | Views |
| trial? | `posts.trial_type` | Type |

## Winner Thresholds
- **is_winner**: views ≥ 100,000 (absolute) — used in Winner Count/Rate charts
- **met_multiplier**: views / per-account median ≥ 2.5x — secondary metric

## Notes
- The green dot (●) in the table marks posts with ≥ 50k views
- Multiplier and Median columns show performance relative to the account's baseline
- Date filter applies to `post_timestamp` (when the reel was published, not scraped)
- All filters are AND-combined
