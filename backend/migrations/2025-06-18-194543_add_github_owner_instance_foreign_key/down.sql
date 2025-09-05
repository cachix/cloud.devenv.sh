-- Remove foreign key constraint from github_owner.instance_id
ALTER TABLE github_owner 
DROP CONSTRAINT github_owner_instance_id_fkey;