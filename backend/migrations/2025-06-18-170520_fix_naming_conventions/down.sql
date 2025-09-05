-- Revert naming convention changes

-- 1. Rename 'git_ref' column back to 'ref' in github_commit table
ALTER TABLE github_commit RENAME COLUMN git_ref TO ref;

-- 2. Rename 'id' column back to 'uuid' in accounts table
ALTER TABLE accounts RENAME COLUMN id TO uuid;

-- 3. Rename 'last_seen_at' back to 'last_seen' in runners table
ALTER TABLE runners RENAME COLUMN last_seen_at TO last_seen;
