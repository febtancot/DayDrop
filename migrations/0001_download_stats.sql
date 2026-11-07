CREATE TABLE IF NOT EXISTS stats_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
INSERT OR IGNORE INTO stats_meta VALUES ('started_at', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'));
CREATE TABLE IF NOT EXISTS daily_stats (
  day TEXT NOT NULL,
  kind TEXT NOT NULL CHECK(kind IN ('website', 'update', 'check', 'direct')),
  version TEXT NOT NULL,
  package_type TEXT NOT NULL CHECK(package_type IN ('full', 'delta', 'feed')),
  count INTEGER NOT NULL DEFAULT 0 CHECK(count >= 0),
  PRIMARY KEY (day, kind, version, package_type)
) WITHOUT ROWID;
