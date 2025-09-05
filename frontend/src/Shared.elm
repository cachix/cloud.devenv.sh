module Shared exposing
    ( Flags, decoder
    , Model, Msg
    , init, update, subscriptions
    )

{-|

@docs Flags, decoder
@docs Model, Msg
@docs init, update, subscriptions

-}

import Api
import Api.Data as Api
import Api.Request.Default as Api
import Dict
import Effect exposing (Effect)
import Json.Decode
import Json.Decode.Pipeline as Decode
import OAuth
import OAuth.AuthorizationCode.PKCE as OAuth
import Oidc
import Oidc.Model
import Oidc.Msg
import RemoteData
import Route exposing (Route)
import Route.Path
import Shared.Model
import Shared.Msg
import Time
import Url exposing (Protocol(..))



-- FLAGS


type alias Flags =
    { now : Time.Posix
    , baseUrl : String
    , authData : Maybe Oidc.Model.AuthData
    , userInfo : Maybe Oidc.Model.UserInfo

    -- OAuth state and challenge for PKCE
    , oauth : OAuthFlags
    , theme : Maybe String
    }


defaultFlags : Flags
defaultFlags =
    { now = Time.millisToPosix 0
    , baseUrl = "http://localhost:8080"
    , authData = Nothing
    , userInfo = Nothing
    , oauth = defaultOAuthFlags
    , theme = Nothing
    }


type alias OAuthFlags =
    { clientId : String
    , audience : String
    , state : Maybe { state : String, codeVerifier : OAuth.CodeVerifier }
    }


defaultOAuthFlags : OAuthFlags
defaultOAuthFlags =
    { clientId = ""
    , audience = ""
    , state = Nothing
    }


decoder : Json.Decode.Decoder Flags
decoder =
    Json.Decode.succeed Flags
        |> Decode.required "now" nowDecoder
        |> Decode.required "baseUrl" Json.Decode.string
        |> Decode.optional "authData" (Json.Decode.maybe Oidc.Model.authDataDecoder) Nothing
        |> Decode.optional "userInfo" (Json.Decode.maybe Oidc.Model.userInfoDecoder) Nothing
        |> Decode.required "oauth" oauthFlagsDecoder
        |> Decode.optional "theme" (Json.Decode.maybe Json.Decode.string) Nothing


nowDecoder : Json.Decode.Decoder Time.Posix
nowDecoder =
    Json.Decode.int
        |> Json.Decode.map Time.millisToPosix


oauthFlagsDecoder : Json.Decode.Decoder OAuthFlags
oauthFlagsDecoder =
    Json.Decode.succeed OAuthFlags
        |> Decode.required "clientId" Json.Decode.string
        |> Decode.required "audience" Json.Decode.string
        |> Decode.required "state" (Json.Decode.nullable oauthStateDecoder)


oauthStateDecoder : Json.Decode.Decoder { state : String, codeVerifier : OAuth.CodeVerifier }
oauthStateDecoder =
    Json.Decode.list Json.Decode.int
        |> Json.Decode.andThen
            (Oidc.convertBytes >> maybeToDecoder "Failed to decode oauthState")


maybeToDecoder : String -> Maybe a -> Json.Decode.Decoder a
maybeToDecoder errMsg maybe =
    case maybe of
        Just a ->
            Json.Decode.succeed a

        Nothing ->
            Json.Decode.fail errMsg



-- INIT


type alias Model =
    Shared.Model.Model


init : Result Json.Decode.Error Flags -> Route () -> ( Model, Effect Msg )
init flagsResult route =
    let
        flags =
            flagsResult
                |> Result.withDefault defaultFlags

        ( oidcAuth, oidcEffect ) =
            initOidcAuth route flags.oauth flags.authData flags.userInfo flags.now

        toUser muserInfo =
            case muserInfo of
                Just userInfo ->
                    RemoteData.Success (Shared.Model.toUser userInfo)

                Nothing ->
                    RemoteData.Loading

        user =
            case oidcAuth.flow of
                Oidc.Model.Authenticated _ ->
                    case oidcAuth.userInfo of
                        Just userInfo ->
                            RemoteData.Success (Shared.Model.toUser userInfo)

                        Nothing ->
                            RemoteData.Loading

                Oidc.Model.NotAuthenticated ->
                    case oidcAuth.userInfo of
                        Just userInfo ->
                            RemoteData.Success (Shared.Model.toUser userInfo)

                        Nothing ->
                            RemoteData.NotAsked

                Oidc.Model.Failed err ->
                    RemoteData.Failure err

                _ ->
                    RemoteData.NotAsked

        model =
            { now = flags.now
            , baseUrl = flags.baseUrl
            , oidcAuth = oidcAuth
            , user = user
            , config = RemoteData.Loading
            , theme =
                flags.theme
                    |> Maybe.map Shared.Model.themeFromString
                    |> Maybe.withDefault Shared.Model.Light
            }
    in
    ( model
    , Effect.batch
        [ Effect.map Shared.Msg.OAuthMsg oidcEffect
        , Api.getConfig
            |> Effect.sendApi (RemoteData.fromResult >> Shared.Msg.GetConfigResponse)
        ]
    )


initOidcAuth : Route () -> OAuthFlags -> Maybe Oidc.Model.AuthData -> Maybe Oidc.Model.UserInfo -> Time.Posix -> ( Oidc.Model.Model, Effect Oidc.Msg.Msg )
initOidcAuth route oauth mauthData muserInfo now =
    let
        config =
            newOidcConfiguration oauth

        redirectUri =
            let
                currentUrl =
                    route.url
            in
            { currentUrl | query = Nothing, fragment = Nothing, path = "/" }

        ( flow, effect ) =
            mauthData
                |> Maybe.map
                    (\auth ->
                        if Oidc.shouldRefreshAccessToken now config auth then
                            ( Oidc.Model.NotAuthenticated
                            , Just (Oidc.Msg.RefreshToken auth.refreshToken)
                            )

                        else
                            ( Oidc.Model.Authenticated auth
                            , Just Oidc.Msg.LoginSucceeded
                            )
                    )
                |> Maybe.withDefault ( Oidc.Model.NotAuthenticated, Nothing )

        oidcAuth =
            { configuration = config
            , flow = flow
            , userInfo = muserInfo
            , redirectUri = redirectUri
            }
    in
    case ( flow, effect ) of
        ( Oidc.Model.NotAuthenticated, Just (Oidc.Msg.RefreshToken _) ) ->
            ( oidcAuth, effect |> Maybe.map Effect.sendMsg |> Maybe.withDefault Effect.none )

        ( Oidc.Model.NotAuthenticated, _ ) ->
            Oidc.init oidcAuth oauth.state route.url

        _ ->
            ( oidcAuth, effect |> Maybe.map Effect.sendMsg |> Maybe.withDefault Effect.none )


newOidcConfiguration : OAuthFlags -> Oidc.Model.Configuration
newOidcConfiguration { clientId, audience } =
    let
        protocol =
            if String.startsWith "https" audience then
                Https

            else
                Http

        origin =
            case protocol of
                Https ->
                    String.dropLeft 8 audience

                Http ->
                    String.dropLeft 7 audience

        ( host, port_ ) =
            case String.split ":" origin of
                [ h, p ] ->
                    ( h, String.toInt p )

                [ h ] ->
                    ( h, Nothing )

                _ ->
                    ( "", Nothing )

        baseUrl =
            { protocol = protocol
            , host = host
            , port_ = port_
            , path = ""
            , query = Nothing
            , fragment = Nothing
            }
    in
    { authorizationEndpoint =
        { baseUrl | path = "/oauth/v2/authorize" }
    , tokenEndpoint =
        { baseUrl | path = "/oauth/v2/token" }
    , userInfoEndpoint =
        { baseUrl | path = "/oidc/v1/userinfo" }
    , clientId = clientId
    , scope =
        [ "openid", "email", "profile", "offline_access" ]
    , refreshThresholdSeconds = 300 -- 5 minutes
    }



-- UPDATE


type alias Msg =
    Shared.Msg.Msg


update : Route () -> Msg -> Model -> ( Model, Effect Msg )
update route msg model =
    case msg of
        Shared.Msg.UpdateNow now ->
            ( { model | now = now }
            , Effect.none
            )

        Shared.Msg.IncomingMsgReceived json ->
            case Json.Decode.decodeValue incomingMsgDecoder json of
                Ok incomingMsg ->
                    ( model, Effect.sendMsg incomingMsg )

                Err _ ->
                    ( model, Effect.none )

        Shared.Msg.OAuthMsg Oidc.Msg.LoginSucceeded ->
            case model.oidcAuth.flow of
                Oidc.Model.Authenticated authData ->
                    ( { model | user = RemoteData.Loading }
                    , Effect.batch
                        [ Effect.sendMsg (Shared.Msg.OAuthMsg Oidc.Msg.UserInfoRequested)
                        , Effect.saveAuthData authData
                        ]
                    )

                _ ->
                    ( model, Effect.none )

        Shared.Msg.OAuthMsg Oidc.Msg.LoginCompleted ->
            case model.oidcAuth.flow of
                Oidc.Model.Failed err ->
                    ( { model | user = RemoteData.Failure err }
                    , Effect.none
                    )

                _ ->
                    case model.oidcAuth.userInfo of
                        Just userInfo ->
                            let
                                redirectEffect =
                                    case route.path of
                                        Route.Path.Home_ ->
                                            -- Redirect authenticated users from landing page to their dashboard
                                            case userInfo.preferred_username of
                                                Just username ->
                                                    Effect.replaceRoute
                                                        { path = Route.Path.Github_Owner_ { owner = username }
                                                        , query = route.query
                                                        , hash = route.hash
                                                        }

                                                Nothing ->
                                                    Effect.none

                                        _ ->
                                            Effect.none
                            in
                            ( { model | user = RemoteData.Success (Shared.Model.toUser userInfo) }
                            , Effect.batch
                                [ Effect.saveUserInfo userInfo
                                , redirectEffect
                                ]
                            )

                        _ ->
                            ( model, Effect.none )

        Shared.Msg.OAuthMsg authMsg ->
            let
                ( newOidcAuth, effect ) =
                    Oidc.update authMsg model.oidcAuth model
            in
            ( { model | oidcAuth = newOidcAuth }, Effect.map Shared.Msg.OAuthMsg effect )

        Shared.Msg.SignIn ->
            ( model, Effect.genRandomBytes 40 )

        Shared.Msg.SignOut ->
            ( { model | user = RemoteData.NotAsked }
            , Effect.batch
                [ Effect.sendMsg (Shared.Msg.OAuthMsg Oidc.Msg.Logout)
                , Effect.clearAuthData
                , Effect.clearUserInfo
                , Effect.replaceRoutePath Route.Path.Home
                ]
            )

        Shared.Msg.GetConfigResponse config ->
            ( { model | config = config }
            , Effect.none
            )

        Shared.Msg.ToggleTheme ->
            let
                newTheme =
                    case model.theme of
                        Shared.Model.Light ->
                            Shared.Model.Dark

                        Shared.Model.Dark ->
                            Shared.Model.Light

                themeString =
                    case newTheme of
                        Shared.Model.Light ->
                            "light"

                        Shared.Model.Dark ->
                            "dark"
            in
            ( { model | theme = newTheme }
            , Effect.setTheme themeString
            )

        Shared.Msg.SetTheme theme ->
            let
                themeString =
                    case theme of
                        Shared.Model.Light ->
                            "light"

                        Shared.Model.Dark ->
                            "dark"
            in
            ( { model | theme = theme }
            , Effect.setTheme themeString
            )

        Shared.Msg.TokenRefreshTick now ->
            case model.oidcAuth.flow of
                Oidc.Model.Authenticated auth ->
                    if Oidc.shouldRefreshAccessToken now model.oidcAuth.configuration auth then
                        ( model, Effect.sendMsg (Shared.Msg.OAuthMsg (Oidc.Msg.RefreshToken auth.refreshToken)) )

                    else
                        ( model, Effect.none )

                _ ->
                    ( model, Effect.none )



-- SUBSCRIPTIONS


subscriptions : Route () -> Model -> Sub Msg
subscriptions _ _ =
    Sub.batch
        [ Time.every 1000 Shared.Msg.UpdateNow
        , Time.every 60000 Shared.Msg.TokenRefreshTick
        , Effect.incoming Shared.Msg.IncomingMsgReceived
        ]



-- HELPERS


incomingMsgDecoder : Json.Decode.Decoder Msg
incomingMsgDecoder =
    Json.Decode.field "tag" Json.Decode.string
        |> Json.Decode.andThen
            (\tag ->
                case tag of
                    "GOT_RANDOM_BYTES" ->
                        gotRandomBytesDecoder

                    -- We no longer handle THEME_CHANGED events from JS
                    -- to avoid circular event triggering
                    _ ->
                        Json.Decode.fail ("Unknown tag: " ++ tag)
            )


gotRandomBytesDecoder : Json.Decode.Decoder Msg
gotRandomBytesDecoder =
    Json.Decode.succeed (Oidc.Msg.GotRandomBytes >> Shared.Msg.OAuthMsg)
        |> Decode.required "data" (Json.Decode.list Json.Decode.int)
