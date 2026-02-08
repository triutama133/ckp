Server scaffold (Node/Express) for VPS or local Docker deployment

Quick overview
- Implements minimal REST endpoints for group invites and membership used by the Flutter client:
  - POST /groups/:groupId/invites  -> create invite (returns token)
  - POST /invites/accept           -> accept invite token (adds member)
  - POST /groups/invites/:id/revoke -> revoke invite
  - GET  /groups/:groupId/members  -> list members
  - POST /groups/:groupId/transfer_ownership -> transfer ownership to another member

Local dev with Docker Compose (recommended):
1. Copy .env.example to .env and adjust `POSTGRES_PASSWORD` if desired.
2. Start services:
   docker-compose up -d
3. Run migrations (the DB schema file is `db.sql` and will be executed by the Postgres container init)
4. Start server:
   npm install
   npm start

Example create-invite request:
  curl -X POST -H "Content-Type: application/json" http://localhost:3000/groups/<groupId>/invites -d '{"createdBy":"alice","ttlSeconds":604800}'

Example accept-invite request:
  curl -X POST -H "Content-Type: application/json" http://localhost:3000/invites/accept -d '{"token":"<token>","userId":"bob"}'

Notes
- This scaffold is intentionally minimal — add authentication (JWT/OAuth), validation, rate-limiting and TLS before production.
- You can adapt these endpoints to Supabase by wiring calls to Supabase RPCs or row-level security policies.
