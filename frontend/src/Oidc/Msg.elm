module Oidc.Msg exposing (Msg(..))

import Http
import OAuth
import OAuth.AuthorizationCode.PKCE as OAuth
import Oidc.Model exposing (UserInfo)


type Msg
    = NoOp
    | StartLogin
    | GotRandomBytes (List Int)
    | GotAccessToken (Result Http.Error OAuth.AuthenticationSuccess)
    | LoginSucceeded
    | UserInfoRequested
    | GotUserInfo (Result Http.Error UserInfo)
    | LoginCompleted
    | RefreshToken (Maybe OAuth.Token)
    | GotRefreshedToken (Result Http.Error OAuth.AuthenticationSuccess)
    | Logout
