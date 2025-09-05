module Shared.Model exposing (Model, Theme(..), User, themeFromString, themeToString, toUser)

import Api.Data as Api
import Oidc.Model
import RemoteData exposing (WebData)
import Time


type alias User =
    Oidc.Model.UserInfo


type Theme
    = Light
    | Dark


type alias Model =
    { now : Time.Posix

    -- The base URL of the backend API
    , baseUrl : String

    -- The current user
    , user : RemoteData.RemoteData Oidc.Model.Error User

    -- OIDC auth state
    , oidcAuth : Oidc.Model.Model

    -- Frontend configuration from backend
    , config : WebData Api.FrontendConfig

    -- Theme (light/dark)
    , theme : Theme
    }


toUser : Oidc.Model.UserInfo -> User
toUser account =
    account


themeToString : Theme -> String
themeToString theme =
    case theme of
        Light ->
            "light"

        Dark ->
            "dark"


themeFromString : String -> Theme
themeFromString str =
    case str of
        "dark" ->
            Dark

        _ ->
            Light
