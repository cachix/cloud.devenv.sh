-- Fix naming convention violations

-- 1. Rename 'ref' column to 'git_ref' in github_commit table (ref is a reserved word)
ALTER TABLE github_commit RENAME COLUMN ref TO git_ref;

-- 2. Rename 'uuid' column to 'id' in accounts table (consistency with other tables)
ALTER TABLE accounts RENAME COLUMN uuid TO id;

-- 3. Rename 'last_seen' to 'last_seen_at' in runners table (consistency with timestamp columns)
ALTER TABLE runners RENAME COLUMN last_seen TO last_seen_at;
