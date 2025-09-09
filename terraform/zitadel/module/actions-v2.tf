# Actions v2 configuration using HTTP provider
# This works around the limitation that the Zitadel provider doesn't support Actions v2 yet

# Data source to read the actions admin PAT
data "local_file" "actions_admin_pat" {
  filename   = "${var.config.state_dir}/actions-admin.pat"
  depends_on = [local_file.actions_admin_pat_file]
}

# Search and delete all existing v2 action targets
resource "null_resource" "cleanup_all_v2_targets" {

  provisioner "local-exec" {
    command = <<-EOT
      echo "Searching for all existing v2 action targets..."
      
      # Search for all targets using the v2 API
      TARGETS_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Accept: application/json" \
        -H "Authorization: Bearer ${data.local_file.actions_admin_pat.content}" \
        -d '{
          "pagination": {
            "offset": 0,
            "limit": 1000,
            "asc": true
          }
        }' \
        "${var.config.insecure ? "http" : "https"}://${var.config.zitadel_domain}:${var.config.zitadel_port}/v2beta/actions/targets/search")
      
      echo "Search response: $TARGETS_RESPONSE"
      
      # Extract target IDs and delete them
      echo "$TARGETS_RESPONSE" | jq -r '.targets[]?.id // empty' | while read -r TARGET_ID; do
        if [ ! -z "$TARGET_ID" ]; then
          echo "Deleting target: $TARGET_ID"
          DELETE_RESPONSE=$(curl -s -X DELETE \
            -H "Accept: application/json" \
            -H "Authorization: Bearer ${data.local_file.actions_admin_pat.content}" \
            "${var.config.insecure ? "http" : "https"}://${var.config.zitadel_domain}:${var.config.zitadel_port}/v2beta/actions/targets/$TARGET_ID")
          echo "Delete response for $TARGET_ID: $DELETE_RESPONSE"
        fi
      done
      
      # Clean up local state files
      rm -f "${var.config.state_dir}/webhook-target-id.txt"
      rm -f "${var.config.state_dir}/actions-v2-config.json"
      rm -f "${var.config.state_dir}/signing-key.txt"
      
      echo "Cleanup completed"
    EOT
  }

  depends_on = [data.local_file.actions_admin_pat]

  triggers = {
    always_run = timestamp()
  }
}

# Create single webhook target for both actions
resource "null_resource" "webhook_target" {

  provisioner "local-exec" {
    command = <<-EOT
      RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer ${data.local_file.actions_admin_pat.content}" \
        -H "Content-Type: application/json" \
        -d '${jsonencode({
    name = "actions_webhook"
    endpoint = "${var.config.base_url}/api/v1/zitadel/actions/webhook"
    timeout = "15s"
    restCall = {
      interruptOnError = false
    }
})}' \
        "${var.config.insecure ? "http" : "https"}://${var.config.zitadel_domain}:${var.config.zitadel_port}/v2beta/actions/targets")
      
      echo "$RESPONSE" > "${var.config.state_dir}/webhook-target-response.json"
      
      TARGET_ID=$(echo "$RESPONSE" | jq -r '.id // empty')
      if [ -z "$TARGET_ID" ]; then
        echo "Failed to create webhook target: $RESPONSE" >&2
        exit 1
      fi
      echo "$TARGET_ID" > "${var.config.state_dir}/webhook-target-id.txt"
      
      # Extract and save the signing key
      SIGNING_KEY=$(echo "$RESPONSE" | jq -r '.signingKey // empty')
      if [ ! -z "$SIGNING_KEY" ]; then
        echo "$SIGNING_KEY" > "${var.config.state_dir}/signing-key.txt"
        echo "Signing key saved to ${var.config.state_dir}/signing-key.txt"
      fi
    EOT
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      if [ -f "${self.triggers.state_dir}/webhook-target-id.txt" ]; then
        TARGET_ID=$(cat "${self.triggers.state_dir}/webhook-target-id.txt")
        curl -s -X DELETE \
          -H "Authorization: Bearer ${self.triggers.token}" \
          "${self.triggers.zitadel_url}/v2beta/actions/targets/$TARGET_ID"
        rm -f "${self.triggers.state_dir}/webhook-target-id.txt"
        rm -f "${self.triggers.state_dir}/webhook-target-response.json"
        rm -f "${self.triggers.state_dir}/signing-key.txt"
      fi
    EOT
  }

  depends_on = [
    data.local_file.actions_admin_pat, 
    null_resource.cleanup_all_v2_targets,
    zitadel_instance_member.actions_admin_role
  ]

  triggers = {
    endpoint    = "${var.config.base_url}/api/v1/zitadel/actions/webhook"
    token       = data.local_file.actions_admin_pat.content
    state_dir   = var.config.state_dir
    zitadel_url = "${var.config.insecure ? "http" : "https"}://${var.config.zitadel_domain}:${var.config.zitadel_port}"
    cleanup_id  = null_resource.cleanup_all_v2_targets.id
  }
}

# Create execution for RetrieveIdentityProviderIntent
resource "null_resource" "retrieve_identity_provider_intent_execution" {

  provisioner "local-exec" {
    command = <<-EOT
      # Wait a moment for the target file to be written
      sleep 2
      
      if [ ! -f "${var.config.state_dir}/webhook-target-id.txt" ]; then
        echo "Error: Webhook target ID file not found after target creation" >&2
        exit 1
      fi
      
      TARGET_ID=$(cat "${var.config.state_dir}/webhook-target-id.txt")
      if [ -z "$TARGET_ID" ]; then
        echo "Error: Webhook target ID is empty" >&2
        exit 1
      fi
      
      echo "Creating execution for RetrieveIdentityProviderIntent with target: $TARGET_ID"
      
      RESPONSE=$(curl -s -X PUT \
        -H "Authorization: Bearer ${data.local_file.actions_admin_pat.content}" \
        -H "Content-Type: application/json" \
        -d "{
          \"condition\": {
            \"response\": {
              \"method\": \"/zitadel.user.v2.UserService/RetrieveIdentityProviderIntent\"
            }
          },
          \"targets\": [\"$TARGET_ID\"]
        }" \
        "${var.config.insecure ? "http" : "https"}://${var.config.zitadel_domain}:${var.config.zitadel_port}/v2beta/actions/executions")
      
      echo "$RESPONSE" > "${var.config.state_dir}/retrieve-identity-provider-intent-execution-response.json"
      
      SET_DATE=$(echo "$RESPONSE" | jq -r '.setDate // empty')
      if [ -z "$SET_DATE" ]; then
        echo "Failed to create RetrieveIdentityProviderIntent execution: $RESPONSE" >&2
        exit 1
      fi
      echo "RetrieveIdentityProviderIntent execution created successfully at: $SET_DATE"
    EOT
  }

  depends_on = [null_resource.webhook_target, data.local_file.actions_admin_pat]

  triggers = {
    target_id   = null_resource.webhook_target.id
    token       = data.local_file.actions_admin_pat.content
    state_dir   = var.config.state_dir
    zitadel_url = "${var.config.insecure ? "http" : "https"}://${var.config.zitadel_domain}:${var.config.zitadel_port}"
    method      = "/zitadel.user.v2.UserService/RetrieveIdentityProviderIntent"
  }
}

# Create execution for CreateSession
resource "null_resource" "create_session_execution" {

  provisioner "local-exec" {
    command = <<-EOT
      # Wait a moment for the target file to be written
      sleep 2
      
      if [ ! -f "${var.config.state_dir}/webhook-target-id.txt" ]; then
        echo "Error: Webhook target ID file not found after target creation" >&2
        exit 1
      fi
      
      TARGET_ID=$(cat "${var.config.state_dir}/webhook-target-id.txt")
      if [ -z "$TARGET_ID" ]; then
        echo "Error: Webhook target ID is empty" >&2
        exit 1
      fi
      
      echo "Creating execution for CreateSession with target: $TARGET_ID"
      
      RESPONSE=$(curl -s -X PUT \
        -H "Authorization: Bearer ${data.local_file.actions_admin_pat.content}" \
        -H "Content-Type: application/json" \
        -d "{
          \"condition\": {
            \"response\": {
              \"method\": \"/zitadel.session.v2.SessionService/CreateSession\"
            }
          },
          \"targets\": [\"$TARGET_ID\"]
        }" \
        "${var.config.insecure ? "http" : "https"}://${var.config.zitadel_domain}:${var.config.zitadel_port}/v2beta/actions/executions")
      
      echo "$RESPONSE" > "${var.config.state_dir}/create-session-execution-response.json"
      
      SET_DATE=$(echo "$RESPONSE" | jq -r '.setDate // empty')
      if [ -z "$SET_DATE" ]; then
        echo "Failed to create CreateSession execution: $RESPONSE" >&2
        exit 1
      fi
      echo "CreateSession execution created successfully at: $SET_DATE"
    EOT
  }

  depends_on = [null_resource.webhook_target, data.local_file.actions_admin_pat]

  triggers = {
    target_id   = null_resource.webhook_target.id
    token       = data.local_file.actions_admin_pat.content
    state_dir   = var.config.state_dir
    zitadel_url = "${var.config.insecure ? "http" : "https"}://${var.config.zitadel_domain}:${var.config.zitadel_port}"
    method      = "/zitadel.session.v2.SessionService/CreateSession"
  }
}


# Create execution for preuserinfo function
resource "null_resource" "preuserinfo_execution" {

  provisioner "local-exec" {
    command = <<-EOT
      # Wait a moment for the target file to be written
      sleep 2
      
      if [ ! -f "${var.config.state_dir}/webhook-target-id.txt" ]; then
        echo "Error: Webhook target ID file not found after target creation" >&2
        exit 1
      fi
      
      TARGET_ID=$(cat "${var.config.state_dir}/webhook-target-id.txt")
      if [ -z "$TARGET_ID" ]; then
        echo "Error: Webhook target ID is empty" >&2
        exit 1
      fi
      
      echo "Creating execution for preuserinfo with target: $TARGET_ID"
      
      RESPONSE=$(curl -s -X PUT \
        -H "Authorization: Bearer ${data.local_file.actions_admin_pat.content}" \
        -H "Content-Type: application/json" \
        -d "{
          \"condition\": {
            \"function\": {
              \"name\": \"preuserinfo\"
            }
          },
          \"targets\": [\"$TARGET_ID\"]
        }" \
        "${var.config.insecure ? "http" : "https"}://${var.config.zitadel_domain}:${var.config.zitadel_port}/v2beta/actions/executions")
      
      echo "$RESPONSE" > "${var.config.state_dir}/preuserinfo-execution-response.json"
      
      SET_DATE=$(echo "$RESPONSE" | jq -r '.setDate // empty')
      if [ -z "$SET_DATE" ]; then
        echo "Failed to create preuserinfo execution: $RESPONSE" >&2
        exit 1
      fi
      echo "Preuserinfo execution created successfully at: $SET_DATE"
    EOT
  }

  depends_on = [null_resource.webhook_target, data.local_file.actions_admin_pat]

  triggers = {
    target_id   = null_resource.webhook_target.id
    token       = data.local_file.actions_admin_pat.content
    state_dir   = var.config.state_dir
    zitadel_url = "${var.config.insecure ? "http" : "https"}://${var.config.zitadel_domain}:${var.config.zitadel_port}"
    function    = "preuserinfo"
  }
}

# Save configuration for reference
resource "local_file" "actions_v2_config" {

  filename = "${var.config.state_dir}/actions-v2-config.json"
  content = jsonencode({
    created_at = timestamp()
    endpoint = "${var.config.base_url}/api/v1/zitadel/actions/webhook"
    methods = {
      retrieve_identity_provider_intent = "/zitadel.user.v2.UserService/RetrieveIdentityProviderIntent"
      create_session                   = "/zitadel.session.v2.SessionService/CreateSession"
      preuserinfo                     = "preuserinfo"
    }
    managed_by = "terraform"
  })

  depends_on = [null_resource.webhook_target]
}

