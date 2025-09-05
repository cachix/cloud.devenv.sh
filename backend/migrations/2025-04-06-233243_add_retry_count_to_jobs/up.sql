ALTER TABLE jobs
ADD COLUMN retried_job_id UUID;

ALTER TABLE jobs
ADD CONSTRAINT fk_retried_job
FOREIGN KEY (retried_job_id)
REFERENCES jobs(id)
ON DELETE SET NULL;
