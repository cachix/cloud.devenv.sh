-- Add the previous_job_id column to the jobs table
ALTER TABLE jobs ADD COLUMN previous_job_id uuid REFERENCES jobs(id) NULL;

-- Copy data from retried_job_id to previous_job_id (in reversed direction)
-- For each job that has been retried, find the job that retried it and set its previous_job_id
UPDATE jobs AS new_job
SET previous_job_id = old_job.id
FROM jobs AS old_job
WHERE old_job.retried_job_id = new_job.id;