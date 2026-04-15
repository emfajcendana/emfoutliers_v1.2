const crypto = require('crypto');

function makeToken(secret) {
  const payload = Buffer.from(JSON.stringify({ ok: true, exp: Date.now() + 12 * 60 * 60 * 1000 })).toString('base64url');
  const sig = crypto.createHmac('sha256', secret).update(payload).digest('base64url');
  return `${payload}.${sig}`;
}

exports.handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method Not Allowed' };
  }

  let body;
  try { body = JSON.parse(event.body); } catch {
    return { statusCode: 400, body: 'Bad Request' };
  }

  const { password } = body;
  if (!password || password !== process.env.DASHBOARD_PASSWORD) {
    return {
      statusCode: 401,
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ error: 'Incorrect password' }),
    };
  }

  const token = makeToken(process.env.JWT_SECRET);
  return {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token }),
  };
};
