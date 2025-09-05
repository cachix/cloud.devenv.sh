use diesel::prelude::*;
use serde::Serialize;
use utoipa::ToSchema;

use crate::schema::accounts;

#[derive(Queryable, Selectable, Debug, Serialize, ToSchema)]
#[diesel(table_name = accounts)]
pub struct Account {
    pub id: uuid::Uuid,
}
