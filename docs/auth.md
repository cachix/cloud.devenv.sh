# OAuth Authorization Flow

Our frontend application uses the OAuth PKCE flow to authenticate users. The flow is as follows:

```
Frontend                     Zitadel                    GitHub (IDP)
     |                          |                           |
     |                          |                           |
     |  1. Initiate OAuth Flow  |                           |
     |------------------------->|                           |
     |                          |                           |
     |  2. Redirect to Zitadel  |                           |
     |<-------------------------|                           |
     |                          |                           |
     |  3. User interacts       |                           |
     |     with Zitadel         |                           |
     |------------------------->|                           |
     |                          |                           |
     |                          |  4. Initiate OAuth        |
     |                          |     with GitHub           |
     |                          |-------------------------->|
     |                          |                           |
     |                          |  5. Redirect to GitHub    |
     |                          |<--------------------------|
     |                          |                           |
     |                          |  6. User authenticates    |
     |                          |     with GitHub           |
     |                          |-------------------------->|
     |                          |                           |
     |                          |  7. Authorization code    |
     |                          |<--------------------------|
     |                          |                           |
     |                          |  8. Exchange code         |
     |                          |     for token             |
     |                          |-------------------------->|
     |                          |                           |
     |                          |  9. Access token          |
     |                          |<--------------------------|
     |                          |                           |
     |  10. Redirect to         |                           |
     |      Frontend callback   |                           |
     |<-------------------------|                           |
     |                          |                           |
     |  11. Exchange code       |                           |
     |      for token           |                           |
     |------------------------->|                           |
     |                          |                           |
     |  12. Access token        |                           |
     |<-------------------------|                           |
```
