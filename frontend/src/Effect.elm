port module Effect exposing
    ( Effect
    , none, batch
    , sendCmd, sendMsg
    , pushRoute, replaceRoute
    , pushRoutePath, replaceRoutePath
    , loadExternalUrl, back
    , map, toCmd
    , clearAuthData, clearUserInfo, genRandomBytes, incoming, outgoing, saveAuthData, saveUserInfo, sendApi, setTheme, signIn, signOut, toggleTheme
    )

{-|

@docs Effect

@docs none, batch
@docs sendCmd, sendMsg

@docs pushRoute, replaceRoute
@docs pushRoutePath, replaceRoutePath
@docs loadExternalUrl, back

@docs map, toCmd

-}

import Api
import Browser.Navigation
import Dict exposing (Dict)
import Http
import Json.Decode
import Json.Encode
import OAuth
import Oidc.Model
import Oidc.Msg
import Route exposing (Route)
import Route.Path
import Shared.Model
import Shared.Msg
import Task
import Time
import Url exposing (Url)


type Effect msg
    = -- BASICS
      None
    | Batch (List (Effect msg))
    | SendCmd (Cmd msg)
      -- ROUTING
    | PushUrl String
    | ReplaceUrl String
    | LoadExternalUrl String
    | Back
      -- SHARED
    | SendSharedMsg Shared.Msg.Msg
      -- LOCAL STORAGE
    | SendToLocalStorage { key : String, value : Json.Encode.Value }
      -- AUTH
    | GenRandomBytes Int
      -- API
    | SendApi
        { request : Api.Request msg
        , onHttpError : Http.Error -> msg
        }



-- PORTS


port outgoing : { tag : String, data : Json.Encode.Value } -> Cmd msg


port incoming : (Json.Encode.Value -> msg) -> Sub msg



-- BASICS


{-| Don't send any effect.
-}
none : Effect msg
none =
    None


{-| Send multiple effects at once.
-}
batch : List (Effect msg) -> Effect msg
batch =
    Batch


{-| Send a normal `Cmd msg` as an effect, something like `Http.get` or `Random.generate`.
-}
sendCmd : Cmd msg -> Effect msg
sendCmd =
    SendCmd


{-| Send a message as an effect. Useful when emitting events from UI components.
-}
sendMsg : msg -> Effect msg
sendMsg msg =
    Task.succeed msg
        |> Task.perform identity
        |> SendCmd



-- ROUTING


{-| Set the new route, and make the back button go back to the current route.
-}
pushRoute :
    { path : Route.Path.Path
    , query : Dict String String
    , hash : Maybe String
    }
    -> Effect msg
pushRoute route =
    PushUrl (Route.toString route)


{-| Same as `Effect.pushRoute`, but without `query` or `hash` support
-}
pushRoutePath : Route.Path.Path -> Effect msg
pushRoutePath path =
    PushUrl (Route.Path.toString path)


{-| Set the new route, but replace the previous one, so clicking the back
button **won't** go back to the previous route.
-}
replaceRoute :
    { path : Route.Path.Path
    , query : Dict String String
    , hash : Maybe String
    }
    -> Effect msg
replaceRoute route =
    ReplaceUrl (Route.toString route)


{-| Same as `Effect.replaceRoute`, but without `query` or `hash` support
-}
replaceRoutePath : Route.Path.Path -> Effect msg
replaceRoutePath path =
    ReplaceUrl (Route.Path.toString path)


{-| Redirect users to a new URL, somewhere external your web application.
-}
loadExternalUrl : String -> Effect msg
loadExternalUrl =
    LoadExternalUrl


{-| Navigate back one page
-}
back : Effect msg
back =
    Back



-- INTERNALS


{-| Elm Land depends on this function to connect pages and layouts
together into the overall app.
-}
map : (msg1 -> msg2) -> Effect msg1 -> Effect msg2
map fn effect =
    case effect of
        None ->
            None

        Batch list ->
            Batch (List.map (map fn) list)

        SendCmd cmd ->
            SendCmd (Cmd.map fn cmd)

        PushUrl url ->
            PushUrl url

        ReplaceUrl url ->
            ReplaceUrl url

        Back ->
            Back

        LoadExternalUrl url ->
            LoadExternalUrl url

        SendSharedMsg sharedMsg ->
            SendSharedMsg sharedMsg

        SendToLocalStorage options ->
            SendToLocalStorage options

        GenRandomBytes n ->
            GenRandomBytes n

        SendApi { request, onHttpError } ->
            SendApi
                { request = Api.map fn request
                , onHttpError = onHttpError >> fn
                }


{-| Elm Land depends on this function to perform your effects.
-}
toCmd :
    { key : Browser.Navigation.Key
    , url : Url
    , shared : Shared.Model.Model
    , fromSharedMsg : Shared.Msg.Msg -> msg
    , batch : List msg -> msg
    , toCmd : msg -> Cmd msg
    }
    -> Effect msg
    -> Cmd msg
toCmd options effect =
    case effect of
        None ->
            Cmd.none

        Batch list ->
            Cmd.batch (List.map (toCmd options) list)

        SendCmd cmd ->
            cmd

        PushUrl url ->
            Browser.Navigation.pushUrl options.key url

        ReplaceUrl url ->
            Browser.Navigation.replaceUrl options.key url

        Back ->
            Browser.Navigation.back options.key 1

        LoadExternalUrl url ->
            Browser.Navigation.load url

        SendSharedMsg sharedMsg ->
            Task.succeed sharedMsg
                |> Task.perform options.fromSharedMsg

        SendToLocalStorage { key, value } ->
            outgoing
                { tag = "SEND_TO_LOCAL_STORAGE"
                , data =
                    Json.Encode.object
                        [ ( "key", Json.Encode.string key )
                        , ( "value", value )
                        ]
                }

        GenRandomBytes n ->
            outgoing { tag = "GEN_RANDOM_BYTES", data = Json.Encode.int n }

        SendApi { request, onHttpError } ->
            let
                oidcAuth =
                    options.shared.oidcAuth

                expect =
                    Http.expectJson
                        (\httpResult ->
                            case httpResult of
                                Ok msg ->
                                    msg

                                Err httpError ->
                                    onHttpError httpError
                        )

                withBearerToken req =
                    case oidcAuth.flow of
                        Oidc.Model.Authenticated auth ->
                            Api.withHeader "Authorization" (OAuth.tokenToString auth.token) req

                        _ ->
                            req
            in
            request
                |> withBearerToken
                |> Api.withBasePath options.shared.baseUrl
                |> Api.sendWithCustomExpect expect


signIn : Effect msg
signIn =
    SendSharedMsg Shared.Msg.SignIn


genRandomBytes : Int -> Effect msg
genRandomBytes n =
    GenRandomBytes n


signOut : Effect msg
signOut =
    SendSharedMsg Shared.Msg.SignOut


saveAuthData : Oidc.Model.AuthData -> Effect msg
saveAuthData auth =
    SendToLocalStorage
        { key = "authData"
        , value = Oidc.Model.encodeAuthData auth
        }


clearAuthData : Effect msg
clearAuthData =
    SendToLocalStorage
        { key = "authData"
        , value = Json.Encode.null
        }


saveUserInfo : Oidc.Model.UserInfo -> Effect msg
saveUserInfo userInfo =
    SendToLocalStorage
        { key = "userInfo"
        , value = Oidc.Model.encodeUserInfo userInfo
        }


clearUserInfo : Effect msg
clearUserInfo =
    SendToLocalStorage
        { key = "userInfo"
        , value = Json.Encode.null
        }


setTheme : String -> Effect msg
setTheme theme =
    outgoing
        { tag = "SET_THEME"
        , data =
            Json.Encode.object
                [ ( "theme", Json.Encode.string theme )
                ]
        }
        |> sendCmd


toggleTheme : Effect msg
toggleTheme =
    SendSharedMsg Shared.Msg.ToggleTheme


{-| Send an API request by converting it into an Effect.

This handles:

  - Authentication: by attaching a bearer token to the request

We take extra care to avoid adding an extra type variable to our Effect type.
This is done by deconstructing the `toMsg` function, so that our `Request a` becomes a `Request msg`.

-}
sendApi : (Result Http.Error a -> msg) -> Api.Request a -> Effect msg
sendApi toMsg (Api.Request req) =
    let
        decoder : Json.Decode.Decoder msg
        decoder =
            req.decoder
                |> Json.Decode.map Ok
                |> Json.Decode.map toMsg

        onHttpError : Http.Error -> msg
        onHttpError httpError =
            toMsg (Err httpError)

        -- Convert `Request a` -> `Request msg`.
        -- This can't be done with the record update syntax.
        request =
            Api.Request
                { method = req.method
                , headers = req.headers
                , basePath = req.basePath
                , pathParams = req.pathParams
                , queryParams = req.queryParams
                , body = req.body
                , decoder = decoder
                , timeout = req.timeout
                , tracker = req.tracker
                }
    in
    SendApi { request = request, onHttpError = onHttpError }
