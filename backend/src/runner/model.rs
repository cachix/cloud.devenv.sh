use crate::schema::runners;
use diesel::prelude::*;
use diesel_async::AsyncPgConnection;
use diesel_async::RunQueryDsl;
use diesel_async::pooled_connection::deadpool::Pool;
use eyre::Result;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

// Import the Job model and types from job module
pub use crate::job::model::{Job, JobStatus, Platform};

#[derive(Debug, Queryable, Selectable, Serialize, Deserialize)]
#[diesel(table_name = runners)]
pub struct Runner {
    pub id: uuid::Uuid,
    pub last_seen_at: chrono::DateTime<chrono::Utc>,
    pub platform: Platform,
    pub created_at: chrono::DateTime<chrono::Utc>,
}

impl Runner {
    pub async fn new(
        pool: &Pool<AsyncPgConnection>,
        platform: Platform,
    ) -> Result<Self, diesel::result::Error> {
        let conn = &mut pool.get().await.unwrap();
        let runner = diesel::insert_into(runners::table)
            .values((
                runners::id.eq(Uuid::now_v7()),
                runners::last_seen_at.eq(chrono::Utc::now()),
                runners::platform.eq(platform),
            ))
            .get_result(conn)
            .await?;

        Ok(runner)
    }

    pub async fn disconnected(
        runner_id: Uuid,
        pool: &Pool<AsyncPgConnection>,
    ) -> Result<(), diesel::result::Error> {
        let conn = &mut pool.get().await.unwrap();
        diesel::update(runners::table)
            .filter(runners::id.eq(runner_id))
            .set(runners::last_seen_at.eq(chrono::Utc::now()))
            .execute(conn)
            .await?;

        Ok(())
    }

    pub async fn get_platform(
        conn: &mut AsyncPgConnection,
        runner_id: &Uuid,
    ) -> Result<String, diesel::result::Error> {
        runners::table
            .filter(runners::id.eq(runner_id))
            .select(runners::platform)
            .first::<String>(conn)
            .await
    }

    pub async fn find_matching_platforms(
        conn: &mut AsyncPgConnection,
        runner_ids: &[Uuid],
        platform: &str,
    ) -> Result<Vec<Uuid>, diesel::result::Error> {
        runners::table
            .filter(runners::id.eq_any(runner_ids))
            .filter(runners::platform.eq(platform))
            .select(runners::id)
            .load::<Uuid>(conn)
            .await
    }
}
