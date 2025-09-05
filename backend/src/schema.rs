// @generated automatically by Diesel CLI.

diesel::table! {
    accounts (id) {
        id -> Uuid,
    }
}

diesel::table! {
    github_commit (id) {
        id -> Uuid,
        rev -> Text,
        repo_id -> Int8,
        git_ref -> Text,
        author -> Text,
        message -> Text,
    }
}

diesel::table! {
    github_installation (id) {
        id -> Int8,
        owner_id -> Int8,
        disabled -> Bool,
    }
}

diesel::table! {
    github_instance (id) {
        id -> Int4,
        host -> Text,
    }
}

diesel::table! {
    github_owner (id) {
        id -> Int8,
        login -> Text,
        name -> Text,
        instance_id -> Int4,
        is_user -> Bool,
    }
}

diesel::table! {
    github_repo (id) {
        id -> Int8,
        name -> Text,
        is_private -> Bool,
        owner_id -> Int8,
        disabled -> Bool,
        generate_pr -> Nullable<Text>,
    }
}

diesel::table! {
    jobs (id) {
        id -> Uuid,
        platform -> Text,
        status -> Text,
        started_at -> Nullable<Timestamptz>,
        finished_at -> Nullable<Timestamptz>,
        runner_id -> Nullable<Uuid>,
        cpus -> Int4,
        memory_mb -> Int8,
        retried_job_id -> Nullable<Uuid>,
        created_at -> Timestamptz,
        previous_job_id -> Nullable<Uuid>,
    }
}

diesel::table! {
    jobs_github (job_id) {
        job_id -> Uuid,
        commit_id -> Uuid,
        check_run_id -> Int8,
    }
}

diesel::table! {
    runners (id) {
        id -> Uuid,
        last_seen_at -> Timestamptz,
        platform -> Text,
        created_at -> Timestamptz,
    }
}

diesel::joinable!(github_commit -> github_repo (repo_id));
diesel::joinable!(github_installation -> github_owner (owner_id));
diesel::joinable!(github_owner -> github_instance (instance_id));
diesel::joinable!(github_repo -> github_owner (owner_id));
diesel::joinable!(jobs_github -> github_commit (commit_id));
diesel::joinable!(jobs_github -> jobs (job_id));

diesel::allow_tables_to_appear_in_same_query!(
    accounts,
    github_commit,
    github_installation,
    github_instance,
    github_owner,
    github_repo,
    jobs,
    jobs_github,
    runners,
);
