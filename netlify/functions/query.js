const jwt = require('jsonwebtoken');
const { createClient } = require('@supabase/supabase-js');

// ── Auth ──────────────────────────────────────────────
function verifyToken(event) {
  const auth = (event.headers['authorization'] || event.headers['Authorization'] || '');
  const token = auth.replace(/^Bearer\s+/i, '');
  if (!token) return false;
  try {
    jwt.verify(token, process.env.JWT_SECRET);
    return true;
  } catch {
    return false;
  }
}

function getDB() {
  return createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_KEY);
}

// ── Helpers ───────────────────────────────────────────
function toArr(val) {
  if (!val) return [];
  if (Array.isArray(val)) return val.filter(Boolean);
  return String(val).split(',').map(s => s.trim()).filter(Boolean);
}

function applyFilters(q, f, activeModels) {
  if (f.dateFrom) q = q.gte('post_timestamp', f.dateFrom);
  if (f.dateTo)   q = q.lte('post_timestamp', f.dateTo);

  const models = toArr(f.model);
  if (models.length)        q = q.in('model', models);
  else if (activeModels && activeModels.length) q = q.in('model', activeModels);

  const usernames = toArr(f.username);
  if (usernames.length) q = q.in('username', usernames);

  const teams = toArr(f.team);
  if (teams.length) q = q.in('team', teams);

  const qms = toArr(f.qm);
  if (qms.length) q = q.in('qm', qms);

  const tms = toArr(f.tm);
  if (tms.length) q = q.in('tm', tms);

  const verticals = toArr(f.vertical);
  if (verticals.length) {
    const orParts = verticals.map(v => `curr_vert.ilike.%${v}%`).join(',');
    q = q.or(orParts);
  }

  return q;
}

function ok(body) {
  return { statusCode: 200, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}
function err(msg, code = 500) {
  return { statusCode: code, headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ error: msg }) };
}

// ── Handler ───────────────────────────────────────────
exports.handler = async (event) => {
  if (!verifyToken(event)) return err('Unauthorized', 401);
  if (event.httpMethod !== 'POST') return { statusCode: 405, body: 'Method Not Allowed' };

  let body;
  try { body = JSON.parse(event.body); } catch { return err('Bad Request', 400); }

  const { action, params = {} } = body;
  const db = getDB();

  try {
    // ── filter_options ────────────────────────────────
    if (action === 'filter_options') {
      const [cfgRes, foRes] = await Promise.all([
        db.from('model_config').select('model_name').eq('is_active', true).order('model_name'),
        db.from('v_filter_options').select('team, qm, tm, curr_vert'),
      ]);

      const activeModels = (cfgRes.data || []).map(r => r.model_name);

      let userRes;
      if (activeModels.length) {
        userRes = await db.from('v_winner_stats_account').select('username').in('model', activeModels).order('username');
      } else {
        userRes = await db.from('v_winner_stats_account').select('username').order('username');
      }

      const fData = foRes.data || [];
      return ok({
        activeModels,
        filterOptions: {
          model:    activeModels,
          team:     [...new Set(fData.map(r => r.team).filter(Boolean))].sort(),
          qm:       [...new Set(fData.map(r => r.qm).filter(Boolean))].sort(),
          tm:       [...new Set(fData.map(r => r.tm).filter(Boolean))].sort(),
          vertical: [...new Set(fData.flatMap(r =>
            String(r.curr_vert || '').split(',').map(v => v.trim()).filter(Boolean)
          ))].sort(),
          username: [...new Set((userRes.data || []).map(r => r.username).filter(Boolean))].sort(),
        },
      });
    }

    // ── top_reels ─────────────────────────────────────
    if (action === 'top_reels') {
      const f            = params.filters || {};
      const activeModels = params.activeModels || [];
      const limit        = params.limit || 50;

      let q = db
        .from('v_top_reels')
        .select('post_url,post_timestamp,model,username,acc_no,owner,qm,tm,curr_vert,views,multiplier_score,median_views,is_winner,trial_type')
        .order('views', { ascending: false })
        .limit(limit);
      q = applyFilters(q, f, activeModels);

      const { data, error } = await q;
      if (error) return err(error.message);
      return ok({ data: data || [] });
    }

    // ── timeline ──────────────────────────────────────
    if (action === 'timeline') {
      const f            = params.filters || {};
      const activeModels = params.activeModels || [];

      // Step 1: top 20 post IDs
      let topQ = db
        .from('v_top_reels')
        .select('post_id')
        .ilike('content_type', '%reel%')
        .order('views', { ascending: false })
        .limit(20);
      topQ = applyFilters(topQ, f, activeModels);

      const { data: topPosts, error: topError } = await topQ;
      if (topError) return err(topError.message);

      const postIds = (topPosts || []).map(r => r.post_id).filter(Boolean);
      if (!postIds.length) return ok({ data: [] });

      let scrapeCutoff = f.dateFrom;
      if (!scrapeCutoff) {
        const end = f.dateTo ? new Date(f.dateTo) : new Date();
        const start = new Date(end);
        start.setDate(start.getDate() - 21);
        scrapeCutoff = start.toISOString().slice(0, 10);
      }

      // Step 2: fetch scrape history
      const { data, error } = await db
        .from('v_views_timeline')
        .select('scrape_date,post_id,post_url,username,views_gained')
        .in('post_id', postIds)
        .gte('scrape_date', scrapeCutoff)
        .order('scrape_date', { ascending: true });

      if (error) return err(error.message);
      return ok({ data: data || [] });
    }

    // ── winner_stats ──────────────────────────────────
    if (action === 'winner_stats') {
      const f            = params.filters || {};
      const activeModels = params.activeModels || [];
      const join         = arr => { const a = toArr(arr); return a.length ? a.join(',') : null; };

      const rpcParams = {
        p_date_from:     f.dateFrom || null,
        p_date_to:       f.dateTo   || null,
        p_model:         join(f.model),
        p_username:      join(f.username),
        p_team:          join(f.team),
        p_qm:            join(f.qm),
        p_tm:            join(f.tm),
        p_vertical:      join(f.vertical),
        p_active_models: (!toArr(f.model).length && activeModels.length) ? activeModels : null,
      };

      const { data, error } = await db.rpc('get_winner_stats', rpcParams);
      if (error) return err(error.message);
      return ok({ data: data || [] });
    }

    // ── winner_count ──────────────────────────────────
    if (action === 'winner_count') {
      const f            = params.filters || {};
      const activeModels = params.activeModels || [];

      let q = db.from('v_top_reels').select('*', { count: 'exact', head: true }).eq('is_winner', true);
      q = applyFilters(q, f, activeModels);

      const { count, error } = await q;
      if (error) return err(error.message);
      return ok({ count: count ?? 0 });
    }

    return err('Unknown action', 400);

  } catch (e) {
    console.error('[query]', e);
    return err(e.message);
  }
};
