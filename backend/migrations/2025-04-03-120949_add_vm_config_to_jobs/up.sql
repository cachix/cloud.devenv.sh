-- Merge of two migrations:
-- 1. add_vm_config_to_jobs - adds cpus and memory columns
-- 2. rename_cpu_and_memory_columns - renames them to a shorter form

-- Add VM configuration columns to jobs
ALTER TABLE "jobs"
ADD COLUMN "cpus" INTEGER;

ALTER TABLE "jobs"
ADD COLUMN "memory_mb" BIGINT;

-- Set default values for existing records
UPDATE "jobs"
SET "cpus" = 2,
    "memory_mb" = 256;

-- Make columns NOT NULL after setting defaults
ALTER TABLE "jobs"
ALTER COLUMN "cpus" SET NOT NULL;

ALTER TABLE "jobs"
ALTER COLUMN "memory_mb" SET NOT NULL;

