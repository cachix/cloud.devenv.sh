-- Add ref column to github_commit table
ALTER TABLE github_commit ADD COLUMN ref TEXT DEFAULT 'main' NOT NULL;