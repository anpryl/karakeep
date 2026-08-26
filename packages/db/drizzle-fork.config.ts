import "dotenv/config";

import type { Config } from "drizzle-kit";

import serverConfig from "@karakeep/shared/config";

// Fork-local migrations. Identical to drizzle.config.ts except for `out` and the
// bookkeeping table, so this fork's migrations never share numbering, a journal file
// or a high-water mark with upstream's. See drizzle-fork/README.md.
//
// The deployed service migrates with `drizzle-kit migrate`, which handles exactly one
// folder/table per invocation, so this needs its own config and its own invocation
// (see the `migrate` helper). Editing packages/db/migrate.ts alone would NOT affect
// production — that file is only used by the in-memory/test path.
const databaseURL = serverConfig.dataDir
  ? `${serverConfig.dataDir}/db.db`
  : "./db.db";

export default {
  dialect: "sqlite",
  schema: "./schema.ts",
  out: "./drizzle-fork",
  migrations: {
    table: "__drizzle_migrations_fork",
  },
  dbCredentials: {
    url: databaseURL,
  },
} satisfies Config;
