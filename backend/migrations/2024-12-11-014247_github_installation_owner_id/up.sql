ALTER TABLE "github_installation"
DROP CONSTRAINT IF EXISTS github_installation_id_fkey;

ALTER TABLE "github_installation"
ADD CONSTRAINT github_installation_owner_id_fkey
FOREIGN KEY ("owner_id") REFERENCES "github_owner" ("id")