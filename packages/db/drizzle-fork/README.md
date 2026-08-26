# Fork-local migrations

Migrations that belong to this fork, kept deliberately apart from upstream's.

They run from this folder against their own bookkeeping table
(`__drizzle_migrations_fork`), configured in `../migrate.ts` and `../drizzle.ts`.
Upstream's `../drizzle/` folder and its `__drizzle_migrations` table are untouched.

## Why

Numbering ours inside upstream's folder does not work. Both sides allocate the next
free integer independently, so they collide: our `0081_add_content_image_status`
and upstream's `0081_add_archived_to_import_staging_bookmarks` are the same number
for different migrations. Worse, `meta/_journal.json` and the schema snapshots are
append-mostly files that BOTH sides edit, so every upstream merge conflicts in them —
including a 3356-line snapshot — and each conflict has to be resolved by hand.

Separating the lineages removes that permanently: two of the eleven files that
conflicted when merging v0.33.2 disappear from the conflict set, and our numbering is
ours alone.

It also removes a trap. Drizzle decides what to apply from a single high-water mark:

```
SELECT id, hash, created_at FROM <table> ORDER BY created_at DESC LIMIT 1
-- then apply every journal entry whose `when` is greater
```

Sharing a table with upstream means our migration's `when` has to sit correctly among
theirs. Renumbering our file while "tidying" its timestamp to match its new position
would make drizzle re-run an already-applied `ALTER TABLE`, fail on a duplicate
column, and — because migrations run in one transaction — roll back every upstream
migration alongside it. With a separate table our timestamps are simply irrelevant to
theirs.

## Adding a migration

`drizzle-kit generate` will NOT do the right thing here: it diffs `schema.ts` against
the snapshots in whichever folder it writes to, and this folder's snapshots do not
describe the full schema. Until that is solved, write the file by hand:

1. `0001_<name>.sql` in this folder.
2. Append an entry to `meta/_journal.json` — `idx` one higher than the last, `when` a
   current epoch-milliseconds value, `tag` matching the filename without `.sql`.
3. Only ever `ALTER` tables upstream already created. Upstream's migrations all run
   before this folder's, but nothing enforces that ordering within a single deploy.

## Existing databases need one-time seeding

`0000_add_content_image_status` was originally applied as upstream-numbered `0081`,
so it is recorded in `__drizzle_migrations`, not in `__drizzle_migrations_fork`. A
database in that state will try to apply it a second time and fail with
`duplicate column name` — taking every upstream migration in the same transaction
down with it.

The file content was preserved byte-for-byte when it moved, so its hash is unchanged
and the row can be copied across verbatim:

```sql
CREATE TABLE IF NOT EXISTS __drizzle_migrations_fork (
  id SERIAL PRIMARY KEY, hash text NOT NULL, created_at numeric
);
INSERT INTO __drizzle_migrations_fork (hash, created_at)
SELECT hash, created_at FROM __drizzle_migrations
WHERE hash = '03b1e76d592fb001840f9e7bf90c90798d6713979724f76c6370bcde7c7dd5ec';
```

That hash is `sha256` of `0000_add_content_image_status.sql`, verified equal to the
value already stored in the production database.

Fresh databases need none of this — they apply it normally.
