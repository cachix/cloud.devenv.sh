ALTER TABLE jobs
DROP CONSTRAINT fk_retried_job;

ALTER TABLE jobs
DROP COLUMN retried_job_id;
