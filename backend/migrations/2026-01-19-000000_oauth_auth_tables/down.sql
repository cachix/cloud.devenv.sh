-- Drop role-based access table
DROP TABLE IF EXISTS account_role;

-- Drop OAuth account linking table
DROP INDEX IF EXISTS oauth_account_ix_account_id;
DROP TABLE IF EXISTS oauth_account;

-- Remove columns from accounts table
ALTER TABLE accounts DROP COLUMN IF EXISTS updated_at;
ALTER TABLE accounts DROP COLUMN IF EXISTS created_at;
ALTER TABLE accounts DROP COLUMN IF EXISTS avatar_url;
ALTER TABLE accounts DROP COLUMN IF EXISTS name;
ALTER TABLE accounts DROP COLUMN IF EXISTS email_verified;
ALTER TABLE accounts DROP COLUMN IF EXISTS email;
