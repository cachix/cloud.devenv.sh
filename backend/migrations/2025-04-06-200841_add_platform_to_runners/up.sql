-- Your SQL goes here
ALTER TABLE "runners" ADD COLUMN "platform" TEXT;
-- Default to x86_64-linux for existing runners
UPDATE "runners" SET "platform" = 'x86_64-linux';
-- Make platform column NOT NULL after setting defaults
ALTER TABLE "runners" ALTER COLUMN "platform" SET NOT NULL;
