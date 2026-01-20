module Shared.Model exposing (Model, Theme(..), User, themeFromString, themeToString)

import Api.Data as Api
import Http
import RemoteData exposing (WebData)
import Time


type alias User =
    { userId : String
    , name : Maybe String
    , email : Maybe String
    , avatarUrl : Maybe String
    , betaAccess : Bool
    }


type Theme
    = Light
    | Dark


type alias Model =
    { now : Time.Posix

    -- The base URL of the backend API
    , baseUrl : String

    -- The current user (fetched from /api/v1/account/me)
    , user : RemoteData.RemoteData Http.Error User

    -- Frontend configuration from backend
    , config : WebData Api.FrontendConfig

    -- Theme (light/dark)
    , theme : Theme
    }


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
