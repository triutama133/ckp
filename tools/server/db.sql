-- Schema for group invites and membership
CREATE TABLE IF NOT EXISTS groups (
  id TEXT PRIMARY KEY,
  name TEXT,
  description TEXT,
  icon TEXT,
  createdAt TIMESTAMPTZ DEFAULT now(),
  createdBy TEXT
);

CREATE TABLE IF NOT EXISTS group_members (
  id TEXT PRIMARY KEY,
  groupId TEXT REFERENCES groups(id) ON DELETE CASCADE,
  userId TEXT,
  role TEXT DEFAULT 'member',
  status TEXT DEFAULT 'invited',
  joinedAt TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(groupId);

CREATE TABLE IF NOT EXISTS group_invites (
  id TEXT PRIMARY KEY,
  groupId TEXT REFERENCES groups(id) ON DELETE CASCADE,
  token TEXT UNIQUE,
  createdBy TEXT,
  createdAt TIMESTAMPTZ DEFAULT now(),
  expiresAt TIMESTAMPTZ,
  usedAt TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_invites_group ON group_invites(groupId);
