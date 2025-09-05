-- Remove author and message columns from github_commit table
ALTER TABLE github_commit DROP COLUMN author;
ALTER TABLE github_commit DROP COLUMN message;





