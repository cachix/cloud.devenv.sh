-- Your SQL goes here
CREATE TABLE "github_instance" (
    "id" INT4 NOT NULL PRIMARY KEY,
    "host" TEXT NOT NULL
);

CREATE TABLE "github_owner" (
    "id" INT8 NOT NULL PRIMARY KEY,
    "login" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "instance_id" INT4 NOT NULL,
    "is_user" BOOL NOT NULL
);

CREATE TABLE "github_repo" (
    "id" INT8 NOT NULL PRIMARY KEY,
    "name" TEXT NOT NULL,
    "is_private" BOOL NOT NULL,
    "owner_id" INT8 NOT NULL,
    "disabled" BOOL NOT NULL,
    FOREIGN KEY ("owner_id") REFERENCES "github_owner" ("id")
);

CREATE TABLE "github_commit" (
    "id" UUID NOT NULL PRIMARY KEY,
    "rev" TEXT NOT NULL,
    "repo_id" INT8 NOT NULL,
    FOREIGN KEY ("repo_id") REFERENCES "github_repo" ("id")
);

CREATE TABLE "jobs" (
    "id" UUID NOT NULL PRIMARY KEY,
    "platform" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "started_at" TIMESTAMPTZ,
    "finished_at" TIMESTAMPTZ,
    "runner_id" UUID
);

CREATE TABLE "jobs_github" (
    "id" UUID NOT NULL PRIMARY KEY,
    "job_id" UUID NOT NULL,
    "commit_id" UUID NOT NULL,
    "check_run_id" INT8 NOT NULL,
    FOREIGN KEY ("job_id") REFERENCES "jobs" ("id"),
    FOREIGN KEY ("commit_id") REFERENCES "github_commit" ("id")
);

CREATE TABLE "runners" (
    "id" UUID NOT NULL PRIMARY KEY,
    "last_seen" TIMESTAMPTZ NOT NULL
);

CREATE TABLE "accounts" ("uuid" UUID NOT NULL PRIMARY KEY);

CREATE TABLE "github_installation" (
    "id" INT8 NOT NULL PRIMARY KEY,
    "owner_id" INT8 NOT NULL,
    "disabled" BOOL NOT NULL,
    FOREIGN KEY ("id") REFERENCES "github_owner" ("id")
);
