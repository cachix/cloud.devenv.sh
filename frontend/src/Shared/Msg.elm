module Shared.Msg exposing (Msg(..))

import Api.Data as Api
import Json.Decode
import Oidc.Msg as Oidc
import RemoteData exposing (WebData)
import Shared.Model exposing (Theme)
import Time


type Msg
    = UpdateNow Time.Posix
    | GetConfigResponse (WebData Api.FrontendConfig)
      -- INCOMING PORT
    | IncomingMsgReceived Json.Decode.Value
      -- AUTH
    | OAuthMsg Oidc.Msg
    | SignIn
    | SignOut
    | TokenRefreshTick Time.Posix
      -- THEME
    | ToggleTheme
    | SetTheme Theme
