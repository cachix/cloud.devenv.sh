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
import Effect exposing (Effect)
import Http
import Json.Decode
import Json.Decode.Pipeline as Decode
import RemoteData
import Route exposing (Route)
import Route.Path
import Shared.Model
import Shared.Msg
import Time



-- FLAGS


type alias Flags =
    { now : Time.Posix
    , baseUrl : String
    , theme : Maybe String
    }


defaultFlags : Flags
defaultFlags =
    { now = Time.millisToPosix 0
    , baseUrl = "http://localhost:8080"
    , theme = Nothing
    }


decoder : Json.Decode.Decoder Flags
decoder =
    Json.Decode.succeed Flags
        |> Decode.required "now" nowDecoder
        |> Decode.required "baseUrl" Json.Decode.string
        |> Decode.optional "theme" (Json.Decode.maybe Json.Decode.string) Nothing


nowDecoder : Json.Decode.Decoder Time.Posix
nowDecoder =
    Json.Decode.int
        |> Json.Decode.map Time.millisToPosix



-- INIT


type alias Model =
    Shared.Model.Model


init : Result Json.Decode.Error Flags -> Route () -> ( Model, Effect Msg )
init flagsResult route =
    let
        flags =
            flagsResult
                |> Result.withDefault defaultFlags

        model =
            { now = flags.now
            , baseUrl = flags.baseUrl
            , user = RemoteData.Loading
            , config = RemoteData.Loading
            , theme =
                flags.theme
                    |> Maybe.map Shared.Model.themeFromString
                    |> Maybe.withDefault Shared.Model.Light
            }
    in
    ( model
    , Effect.batch
        [ -- Fetch user info to check if logged in
          fetchCurrentUser
        , -- Fetch frontend config
          Api.getConfig
            |> Effect.sendApi (RemoteData.fromResult >> Shared.Msg.GetConfigResponse)
        ]
    )


fetchCurrentUser : Effect Msg
fetchCurrentUser =
    Effect.sendCmd
        (Http.get
            { url = "/api/v1/account/me"
            , expect = Http.expectJson Shared.Msg.GotUser userDecoder
            }
        )


userDecoder : Json.Decode.Decoder Shared.Model.User
userDecoder =
    Json.Decode.succeed Shared.Model.User
        |> Decode.required "user_id" Json.Decode.string
        |> Decode.optional "name" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Decode.optional "email" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Decode.optional "avatar_url" (Json.Decode.nullable Json.Decode.string) Nothing
        |> Decode.optional "beta_access" Json.Decode.bool False



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

        Shared.Msg.GotUser result ->
            case result of
                Ok user ->
                    ( { model | user = RemoteData.Success user }
                    , -- Redirect authenticated users from landing page to their dashboard
                      case route.path of
                        Route.Path.Home_ ->
                            case user.name of
                                Just name ->
                                    Effect.replaceRoute
                                        { path = Route.Path.Github_Owner_ { owner = name }
                                        , query = route.query
                                        , hash = route.hash
                                        }

                                Nothing ->
                                    Effect.none

                        _ ->
                            Effect.none
                    )

                Err err ->
                    case err of
                        Http.BadStatus 401 ->
                            -- Not authenticated - this is expected for non-logged-in users
                            ( { model | user = RemoteData.NotAsked }
                            , Effect.none
                            )

                        Http.BadStatus 403 ->
                            -- Forbidden (no beta access) - still not authenticated for our purposes
                            ( { model | user = RemoteData.NotAsked }
                            , Effect.none
                            )

                        _ ->
                            -- Actual error (network issue, server error, etc.)
                            ( { model | user = RemoteData.Failure err }
                            , Effect.none
                            )

        Shared.Msg.SignIn ->
            -- Redirect to OAuth sign-in endpoint
            ( model
            , Effect.loadExternalUrl "/auth/signin/github"
            )

        Shared.Msg.SignOut ->
            -- Redirect to OAuth sign-out endpoint
            ( { model | user = RemoteData.NotAsked }
            , Effect.loadExternalUrl "/auth/signout"
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



-- SUBSCRIPTIONS


subscriptions : Route () -> Model -> Sub Msg
subscriptions _ _ =
    Time.every 1000 Shared.Msg.UpdateNow
