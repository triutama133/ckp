require('dotenv').config();
const express = require('express');
const { v4: uuidv4 } = require('uuid');
const { Pool } = require('pg');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json());

const DATABASE_URL = process.env.DATABASE_URL || 'postgres://postgres:postgres@localhost:5432/ckp';
const pool = new Pool({ connectionString: DATABASE_URL });

app.get('/', (req, res) => res.json({ ok: true }));

// Create invite
app.post('/groups/:groupId/invites', async (req, res) => {
  const { groupId } = req.params;
  const { createdBy, ttlSeconds } = req.body || {};
  try {
    const id = 'inv_' + uuidv4();
    const token = 't_' + Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
    const createdAt = new Date();
    const expiresAt = ttlSeconds ? new Date(Date.now() + ttlSeconds * 1000) : new Date(Date.now() + 7 * 24 * 3600 * 1000);
    const sql = `INSERT INTO group_invites (id, groupId, token, createdBy, createdAt, expiresAt) VALUES ($1,$2,$3,$4,$5,$6)`;
    await pool.query(sql, [id, groupId, token, createdBy || 'system', createdAt, expiresAt]);
    res.json({ id, groupId, token, createdBy: createdBy || 'system', createdAt, expiresAt });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e) });
  }
});

// Accept invite
app.post('/invites/accept', async (req, res) => {
  const { token, userId } = req.body || {};
  if (!token || !userId) return res.status(400).json({ error: 'token and userId required' });
  try {
    const { rows } = await pool.query('SELECT * FROM group_invites WHERE token = $1', [token]);
    if (rows.length === 0) return res.status(404).json({ error: 'invite not found' });
    const invite = rows[0];
    if (invite.usedat) return res.status(400).json({ error: 'invite already used' });
    if (invite.expiresat && new Date(invite.expiresat) < new Date()) return res.status(400).json({ error: 'invite expired' });

    // create group member
    const memberId = 'gm_' + uuidv4();
    const joinedAt = new Date();
    await pool.query('INSERT INTO group_members(id, groupId, userId, role, status, joinedAt) VALUES ($1,$2,$3,$4,$5,$6)', [memberId, invite.groupid, userId, 'member', 'accepted', joinedAt]);
    await pool.query('UPDATE group_invites SET usedAt = $1 WHERE id = $2', [new Date(), invite.id]);
    res.json({ id: memberId, groupId: invite.groupid, userId, role: 'member', status: 'accepted', joinedAt });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e) });
  }
});

// Revoke invite
app.post('/groups/invites/:id/revoke', async (req, res) => {
  const { id } = req.params;
  try {
    await pool.query('DELETE FROM group_invites WHERE id = $1', [id]);
    res.json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e) });
  }
});

// List members
app.get('/groups/:groupId/members', async (req, res) => {
  const { groupId } = req.params;
  try {
    const { rows } = await pool.query('SELECT * FROM group_members WHERE groupId = $1 ORDER BY joinedAt DESC', [groupId]);
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: String(e) });
  }
});

// Transfer ownership
app.post('/groups/:groupId/transfer_ownership', async (req, res) => {
  const { groupId } = req.params;
  const { newMemberId } = req.body || {};
  if (!newMemberId) return res.status(400).json({ error: 'newMemberId required' });
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    // demote current owner
    await client.query('UPDATE group_members SET role = $1 WHERE groupId = $2 AND role = $3', ['admin', groupId, 'owner']);
    // promote new owner
    await client.query('UPDATE group_members SET role = $1 WHERE id = $2', ['owner', newMemberId]);
    // update groups.createdBy
    const { rows } = await client.query('SELECT userId FROM group_members WHERE id = $1', [newMemberId]);
    if (rows.length > 0) {
      const uid = rows[0].userid;
      await client.query('UPDATE groups SET createdBy = $1 WHERE id = $2', [uid, groupId]);
    }
    await client.query('COMMIT');
    res.json({ ok: true });
  } catch (e) {
    await client.query('ROLLBACK');
    console.error(e);
    res.status(500).json({ error: String(e) });
  } finally {
    client.release();
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log('Server listening on port', port));
