-- Add foreign key constraint from github_owner.instance_id to github_instance.id
ALTER TABLE github_owner 
ADD CONSTRAINT github_owner_instance_id_fkey 
FOREIGN KEY (instance_id) 
REFERENCES github_instance (id);