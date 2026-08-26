import { migrate } from "drizzle-orm/better-sqlite3/migrator";

import { db } from "./drizzle";

migrate(db, { migrationsFolder: "./drizzle" });

// Fork-local migrations run from their OWN folder against their OWN bookkeeping table.
// Upstream's call above is left exactly as upstream wrote it.
//
// This keeps the two lineages from ever touching. Numbering ours from 0000 in a
// separate folder means an upstream migration can never collide with ours (both sides
// reached 0081 before this), and, more importantly, meta/_journal.json and the schema
// snapshots stop conflicting on every single upstream merge.
//
// Ordering is safe because ours only ever ALTERs tables upstream has already created:
// upstream's migrations all run before this call.
//
// See packages/db/drizzle-fork/README.md before adding a migration here.
migrate(db, {
  migrationsFolder: "./drizzle-fork",
  migrationsTable: "__drizzle_migrations_fork",
});
