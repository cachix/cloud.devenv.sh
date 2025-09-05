-- Add GitHub handle (as author) and message columns to github_commit table
ALTER TABLE github_commit 
ADD COLUMN author TEXT NULL,
ADD COLUMN message TEXT NULL;

-- Set default values for existing rows
UPDATE github_commit 
SET author = 'Unknown', 
    message = 'No message provided';

-- Make columns NOT NULL after populating with default values
ALTER TABLE github_commit 
ALTER COLUMN author SET NOT NULL,
ALTER COLUMN message SET NOT NULL;




