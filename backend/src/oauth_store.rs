//! PostgreSQL-backed UserStore implementation for oauth-kit.
//!
//! This module provides a UserStore implementation that persists OAuth user data
//! to PostgreSQL, linking OAuth provider accounts to local user accounts.

use async_trait::async_trait;
use diesel::prelude::*;
use diesel_async::scoped_futures::ScopedFutureExt;
use diesel_async::{AsyncConnection, RunQueryDsl};
use oauth_kit::{User, UserStore};
use thiserror::Error;
use uuid::Uuid;

use crate::config::DbPool;
use crate::schema::{accounts, oauth_account};

/// Error type for PostgreSQL user store operations.
#[derive(Debug, Error)]
pub enum PostgresStoreError {
    #[error("Database error: {0}")]
    Database(#[from] diesel::result::Error),

    #[error("Pool error: {0}")]
    Pool(String),
}

/// PostgreSQL-backed user store for OAuth authentication.
///
/// This store links OAuth provider accounts to local user accounts in the database.
/// When a user authenticates via OAuth, we either find an existing account linked
/// to that provider identity or create a new account.
#[derive(Clone)]
pub struct PostgresUserStore {
    pool: DbPool,
}

impl PostgresUserStore {
    /// Creates a new PostgresUserStore with the given database connection pool.
    pub fn new(pool: DbPool) -> Self {
        Self { pool }
    }
}

/// Insertable struct for creating new accounts.
#[derive(Insertable)]
#[diesel(table_name = accounts)]
struct NewAccount {
    id: Uuid,
    email: Option<String>,
    email_verified: bool,
    name: Option<String>,
    avatar_url: Option<String>,
}

/// Insertable struct for creating OAuth account links.
#[derive(Insertable)]
#[diesel(table_name = oauth_account)]
struct NewOAuthAccount {
    id: Uuid,
    account_id: Uuid,
    provider: String,
    provider_account_id: String,
    provider_email: Option<String>,
    raw_profile: Option<serde_json::Value>,
}

/// Query struct for finding OAuth accounts.
#[derive(Queryable, Selectable)]
#[diesel(table_name = oauth_account)]
struct OAuthAccountLookup {
    account_id: Uuid,
}

#[async_trait]
impl UserStore for PostgresUserStore {
    type UserId = Uuid;
    type Error = PostgresStoreError;

    /// Find or create a user from an OAuth profile.
    ///
    /// This method:
    /// 1. Looks up an existing oauth_account by (provider, provider_account_id)
    /// 2. If found, returns the linked account_id
    /// 3. If not found, creates a new account and oauth_account link in a transaction
    async fn find_or_create(&self, user: &User, provider: &str) -> Result<Uuid, Self::Error> {
        let mut conn = self
            .pool
            .get()
            .await
            .map_err(|e| PostgresStoreError::Pool(e.to_string()))?;

        // Try to find existing OAuth account link
        let existing: Option<OAuthAccountLookup> = oauth_account::table
            .filter(oauth_account::provider.eq(provider))
            .filter(oauth_account::provider_account_id.eq(&user.id))
            .select(OAuthAccountLookup::as_select())
            .first(&mut conn)
            .await
            .optional()?;

        if let Some(oauth_acc) = existing {
            // Update the account with latest profile data
            diesel::update(accounts::table.filter(accounts::id.eq(oauth_acc.account_id)))
                .set((
                    accounts::email.eq(&user.email),
                    accounts::email_verified.eq(user.email_verified),
                    accounts::name.eq(&user.name),
                    accounts::avatar_url.eq(&user.image),
                    accounts::updated_at.eq(diesel::dsl::now),
                ))
                .execute(&mut conn)
                .await?;

            return Ok(oauth_acc.account_id);
        }

        // Create new account and OAuth link in a transaction
        let user_email = user.email.clone();
        let user_email_verified = user.email_verified;
        let user_name = user.name.clone();
        let user_image = user.image.clone();
        let user_id = user.id.clone();
        let user_raw = user.raw.clone();
        let provider_owned = provider.to_string();

        let account_id = conn
            .transaction::<_, PostgresStoreError, _>(|conn| {
                async move {
                    let account_id = Uuid::now_v7();
                    let new_account = NewAccount {
                        id: account_id,
                        email: user_email.clone(),
                        email_verified: user_email_verified,
                        name: user_name,
                        avatar_url: user_image,
                    };

                    diesel::insert_into(accounts::table)
                        .values(&new_account)
                        .execute(conn)
                        .await?;

                    let oauth_account_id = Uuid::now_v7();
                    let new_oauth_account = NewOAuthAccount {
                        id: oauth_account_id,
                        account_id,
                        provider: provider_owned,
                        provider_account_id: user_id,
                        provider_email: user_email,
                        raw_profile: if user_raw.is_null() {
                            None
                        } else {
                            Some(user_raw)
                        },
                    };

                    diesel::insert_into(oauth_account::table)
                        .values(&new_oauth_account)
                        .execute(conn)
                        .await?;

                    Ok(account_id)
                }
                .scope_boxed()
            })
            .await?;

        tracing::info!(
            account_id = %account_id,
            provider = %provider,
            provider_account_id = %user.id,
            "Created new account from OAuth authentication"
        );

        Ok(account_id)
    }

    /// Link an additional OAuth provider to an existing user.
    async fn link_account(
        &self,
        user_id: &Uuid,
        user: &User,
        provider: &str,
    ) -> Result<(), Self::Error> {
        let mut conn = self
            .pool
            .get()
            .await
            .map_err(|e| PostgresStoreError::Pool(e.to_string()))?;

        let oauth_account_id = Uuid::now_v7();
        let new_oauth_account = NewOAuthAccount {
            id: oauth_account_id,
            account_id: *user_id,
            provider: provider.to_string(),
            provider_account_id: user.id.clone(),
            provider_email: user.email.clone(),
            raw_profile: if user.raw.is_null() {
                None
            } else {
                Some(user.raw.clone())
            },
        };

        diesel::insert_into(oauth_account::table)
            .values(&new_oauth_account)
            .on_conflict_do_nothing()
            .execute(&mut conn)
            .await?;

        tracing::info!(
            account_id = %user_id,
            provider = %provider,
            "Linked OAuth provider to existing account"
        );

        Ok(())
    }
}
