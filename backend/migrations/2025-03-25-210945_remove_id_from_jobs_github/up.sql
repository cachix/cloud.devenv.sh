-- Your SQL goes here

-- First create a temporary table with the new schema
CREATE TABLE jobs_github_new (
    job_id UUID NOT NULL PRIMARY KEY,
    commit_id UUID NOT NULL,
    check_run_id INT8 NOT NULL,
    FOREIGN KEY (job_id) REFERENCES jobs (id),
    FOREIGN KEY (commit_id) REFERENCES github_commit (id)
);

-- Copy data from old table to new table
INSERT INTO jobs_github_new
SELECT job_id, commit_id, check_run_id
FROM jobs_github;

-- Drop old table
DROP TABLE jobs_github;

-- Rename new table to original name
ALTER TABLE jobs_github_new RENAME TO jobs_github;
