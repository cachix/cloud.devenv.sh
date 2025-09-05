-- This file should undo anything in `up.sql`

-- Create a temporary table with the old schema
CREATE TABLE jobs_github_old (
    id UUID NOT NULL PRIMARY KEY,
    job_id UUID NOT NULL,
    commit_id UUID NOT NULL,
    check_run_id INT8 NOT NULL,
    FOREIGN KEY (job_id) REFERENCES jobs (id),
    FOREIGN KEY (commit_id) REFERENCES github_commit (id)
);

-- Copy data from new table to old table, generating new UUIDs
INSERT INTO jobs_github_old (id, job_id, commit_id, check_run_id)
SELECT uuid_generate_v7(), job_id, commit_id, check_run_id
FROM jobs_github;

-- Drop new table
DROP TABLE jobs_github;

-- Rename old table to original name
ALTER TABLE jobs_github_old RENAME TO jobs_github;
