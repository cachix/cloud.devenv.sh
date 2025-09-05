-- This file should undo anything in `up.sql`

ALTER TABLE "jobs"
DROP COLUMN "created_at";

ALTER TABLE "runners"
DROP COLUMN "created_at";
