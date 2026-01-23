# OAuth Authorization Flow

Authentication uses oauth-kit with GitHub as the OAuth provider. Session cookies manage user state.

```
Frontend                     Backend (oauth-kit)              GitHub
     |                              |                           |
     |  1. Click "Sign In"          |                           |
     |----------------------------->|                           |
     |     GET /auth/signin/github  |                           |
     |                              |                           |
     |  2. Redirect to GitHub       |                           |
     |<-----------------------------|                           |
     |                              |                           |
     |  3. User authenticates       |                           |
     |  -------------------------------------------------------->|
     |                              |                           |
     |  4. GitHub redirects back    |                           |
     |     with authorization code  |                           |
     |<----------------------------------------------------------|
     |     GET /auth/callback/github?code=...                   |
     |----------------------------->|                           |
     |                              |                           |
     |                              |  5. Exchange code for     |
     |                              |     access token          |
     |                              |-------------------------->|
     |                              |                           |
     |                              |  6. Fetch user profile    |
     |                              |-------------------------->|
     |                              |                           |
     |                              |  7. Find or create user   |
     |                              |     in database           |
     |                              |                           |
     |  8. Set session cookie       |                           |
     |     and redirect to /        |                           |
     |<-----------------------------|                           |
     |                              |                           |
     |  9. GET /api/v1/account/me   |                           |
     |----------------------------->|                           |
     |     (with session cookie)    |                           |
     |                              |                           |
     |  10. Return user info        |                           |
     |<-----------------------------|                           |
```

## Database Schema

- `accounts` - User accounts with email, name, avatar_url
- `oauth_account` - Links OAuth provider identities to accounts
- `account_role` - Role-based access control (e.g., `beta_user`)

## Sign Out

`GET /auth/signout` clears the session cookie and redirects to `/`.
