module Shared.Msg exposing (Msg(..))

import Api.Data as Api
import Http
import RemoteData exposing (WebData)
import Shared.Model exposing (Theme, User)
import Time


type Msg
    = UpdateNow Time.Posix
    | GetConfigResponse (WebData Api.FrontendConfig)
      -- AUTH
    | SignIn
    | SignOut
    | GotUser (Result Http.Error User)
      -- THEME
    | ToggleTheme
    | SetTheme Theme
