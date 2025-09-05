module Oidc exposing (convertBytes, gotRandomBytes, init, shouldRefreshAccessToken, toBytes, update)

import Base64.Encode as Base64
import Bytes exposing (Bytes)
import Bytes.Encode as Bytes
import Effect exposing (Effect)
import Http
import Json.Decode as Json
import Json.Encode as E
import OAuth
import OAuth.AuthorizationCode.PKCE as OAuth
import OAuth.Refresh
import Oidc.Model
import Oidc.Msg
import Route.Path
import Time
import Url exposing (Protocol(..), Url)


type alias Model =
    Oidc.Model.Model


type alias Flow =
    Oidc.Model.Flow


type alias Configuration =
    Oidc.Model.Configuration


type alias Msg =
    Oidc.Msg.Msg


init : Model -> Maybe { state : String, codeVerifier : OAuth.CodeVerifier } -> Url -> ( Model, Effect Msg )
init model mflags origin =
    let
        redirectUri =
            { origin | query = Nothing, fragment = Nothing }

        clearUrl =
            Effect.replaceRoutePath (Route.Path.fromUrl redirectUri)
    in
    case OAuth.parseCode origin of
        OAuth.Empty ->
            ( { model | flow = Oidc.Model.NotAuthenticated }
            , Effect.none
            )

        -- It is important to set a `state` when making the authorization request
        -- and to verify it after the redirection. The state can be anything but its primary
        -- usage is to prevent cross-site request forgery; at minima, it should be a short,
        -- non-guessable string, generated on the fly.
        --
        -- We remember any previously generated state using the browser's local storage
        -- and give it back (if present) to the elm application upon start
        OAuth.Success { code, state } ->
            case mflags of
                Nothing ->
                    ( { model | flow = Oidc.Model.Failed Oidc.Model.ErrStateMismatch }
                    , clearUrl
                    )

                Just flags ->
                    if state /= Just flags.state then
                        ( { model | flow = Oidc.Model.Failed Oidc.Model.ErrStateMismatch }
                        , clearUrl
                        )

                    else
                        ( { model | flow = Oidc.Model.Authenticating code flags.codeVerifier }
                        , Effect.batch
                            [ getAccessToken model.configuration model.redirectUri code flags.codeVerifier
                            , clearUrl
                            ]
                        )

        OAuth.Error error ->
            ( { model | flow = Oidc.Model.Failed <| Oidc.Model.ErrAuthorization error }
            , clearUrl
            )


getAccessToken : Configuration -> Url -> OAuth.AuthorizationCode -> OAuth.CodeVerifier -> Effect Msg
getAccessToken { clientId, tokenEndpoint } redirectUri code codeVerifier =
    Effect.sendCmd <|
        Http.request <|
            OAuth.makeTokenRequest Oidc.Msg.GotAccessToken
                { credentials =
                    { clientId = clientId
                    , secret = Nothing
                    }
                , code = code
                , codeVerifier = codeVerifier
                , url = tokenEndpoint
                , redirectUri = redirectUri
                }


update : Msg -> Model -> { shared | now : Time.Posix } -> ( Model, Effect Msg )
update msg model shared =
    case ( model.flow, msg ) of
        ( Oidc.Model.NotAuthenticated, Oidc.Msg.StartLogin ) ->
            startLogin model

        ( Oidc.Model.NotAuthenticated, Oidc.Msg.GotRandomBytes bytes ) ->
            gotRandomBytes model bytes

        ( Oidc.Model.Authenticating _ _, Oidc.Msg.GotAccessToken authenticationResponse ) ->
            gotAccessToken model shared.now authenticationResponse

        ( Oidc.Model.Authenticated auth, Oidc.Msg.UserInfoRequested ) ->
            userInfoRequested model auth.token

        ( Oidc.Model.Authenticated _, Oidc.Msg.GotUserInfo userInfoResponse ) ->
            gotUserInfo model userInfoResponse

        ( Oidc.Model.NotAuthenticated, Oidc.Msg.RefreshToken auth ) ->
            requestRefreshToken model auth

        ( Oidc.Model.Authenticated auth, Oidc.Msg.RefreshToken _ ) ->
            requestRefreshToken model auth.refreshToken

        ( _, Oidc.Msg.GotRefreshedToken authenticationResponse ) ->
            gotRefreshedToken model shared.now authenticationResponse

        ( _, Oidc.Msg.Logout ) ->
            logout model

        _ ->
            noOp model


noOp : Model -> ( Model, Effect msg )
noOp model =
    ( model, Effect.none )


gotRandomBytes : Model -> List Int -> ( Model, Effect Msg )
gotRandomBytes model bytes =
    case convertBytes bytes of
        Nothing ->
            ( { model | flow = Oidc.Model.Failed Oidc.Model.ErrFailedToConvertBytes }
            , Effect.none
            )

        Just { state, codeVerifier } ->
            let
                authorization =
                    { clientId = model.configuration.clientId
                    , redirectUri = model.redirectUri
                    , scope = model.configuration.scope
                    , state = Just state
                    , codeChallenge = OAuth.mkCodeChallenge codeVerifier
                    , url = model.configuration.authorizationEndpoint
                    }
            in
            ( { model | flow = Oidc.Model.NotAuthenticated }
            , authorization
                |> OAuth.makeAuthorizationUrl
                |> Url.toString
                |> Effect.loadExternalUrl
            )


startLogin : Model -> ( Model, Effect Msg )
startLogin model =
    ( { model | flow = Oidc.Model.NotAuthenticated }
      -- We generate random bytes for both the state and the code verifier. First bytes are
      -- for the 'state', and remaining ones are used for the code verifier.
    , Effect.genRandomBytes (cSTATE_SIZE + cCODE_VERIFIER_SIZE)
    )



-- Helper function to handle successful authentication


handleAuthSuccess : Model -> Time.Posix -> OAuth.AuthenticationSuccess -> Effect Msg -> ( Model, Effect Msg )
handleAuthSuccess model now authSuccess extraEffect =
    let
        auth =
            Oidc.Model.authDataFromAuthenticationSuccess now authSuccess
    in
    ( { model | flow = Oidc.Model.Authenticated auth }
    , Effect.batch
        [ extraEffect
        , Effect.saveAuthData auth
        ]
    )


gotAccessToken : Model -> Time.Posix -> Result Http.Error OAuth.AuthenticationSuccess -> ( Model, Effect Msg )
gotAccessToken model now authenticationResponse =
    case authenticationResponse of
        Err (Http.BadBody body) ->
            case Json.decodeString OAuth.defaultAuthenticationErrorDecoder body of
                Ok error ->
                    ( { model | flow = Oidc.Model.Failed <| Oidc.Model.ErrAuthentication error }
                    , Effect.none
                    )

                _ ->
                    ( { model | flow = Oidc.Model.Failed Oidc.Model.ErrHTTPGetAccessToken }
                    , Effect.none
                    )

        Err _ ->
            ( { model | flow = Oidc.Model.Failed Oidc.Model.ErrHTTPGetAccessToken }
            , Effect.none
            )

        Ok authData ->
            handleAuthSuccess model now authData (Effect.sendMsg Oidc.Msg.LoginSucceeded)


requestRefreshToken : Model -> Maybe OAuth.Token -> ( Model, Effect Msg )
requestRefreshToken model mrefreshToken =
    ( model
    , mrefreshToken
        |> Maybe.map
            (\refreshToken ->
                Effect.sendCmd <|
                    Http.request <|
                        OAuth.Refresh.makeTokenRequest Oidc.Msg.GotRefreshedToken
                            { credentials =
                                Just
                                    { clientId = model.configuration.clientId
                                    , secret = ""
                                    }
                            , url = model.configuration.tokenEndpoint
                            , scope = model.configuration.scope
                            , token = refreshToken
                            }
            )
        |> Maybe.withDefault Effect.none
    )


gotRefreshedToken : Model -> Time.Posix -> Result Http.Error OAuth.AuthenticationSuccess -> ( Model, Effect Msg )
gotRefreshedToken =
    gotAccessToken


userInfoRequested : Model -> OAuth.Token -> ( Model, Effect Msg )
userInfoRequested model token =
    ( model, getUserInfo model token )


getUserInfo : Model -> OAuth.Token -> Effect Msg
getUserInfo model token =
    Effect.sendCmd <|
        Http.request
            { method = "GET"
            , body = Http.emptyBody
            , headers = OAuth.useToken token []
            , url = Url.toString model.configuration.userInfoEndpoint
            , expect = Http.expectJson Oidc.Msg.GotUserInfo Oidc.Model.userInfoDecoder
            , timeout = Nothing
            , tracker = Nothing
            }


gotUserInfo : Model -> Result Http.Error Oidc.Model.UserInfo -> ( Model, Effect Msg )
gotUserInfo model userInfoResponse =
    case userInfoResponse of
        Err _ ->
            ( { model | flow = Oidc.Model.Failed Oidc.Model.ErrHTTPGetUserInfo }
            , Effect.sendMsg Oidc.Msg.Logout
            )

        Ok userInfo ->
            ( { model | userInfo = Just userInfo }
            , Effect.sendMsg Oidc.Msg.LoginCompleted
            )


logout : Model -> ( Model, Effect Msg )
logout model =
    ( { model | flow = Oidc.Model.NotAuthenticated, userInfo = Nothing }
    , Effect.batch
        [ Effect.clearAuthData
        , Effect.clearUserInfo
        , Effect.loadExternalUrl (Url.toString model.redirectUri)
        ]
    )



--
-- Helpers
--


cSTATE_SIZE : Int
cSTATE_SIZE =
    8



-- Number of bytes making the 'code_verifier'


cCODE_VERIFIER_SIZE : Int
cCODE_VERIFIER_SIZE =
    32


toBytes : List Int -> Bytes
toBytes =
    List.map Bytes.unsignedInt8 >> Bytes.sequence >> Bytes.encode


base64 : Bytes -> String
base64 =
    Base64.bytes >> Base64.encode


convertBytes : List Int -> Maybe { state : String, codeVerifier : OAuth.CodeVerifier }
convertBytes bytes =
    if List.length bytes < (cSTATE_SIZE + cCODE_VERIFIER_SIZE) then
        Nothing

    else
        let
            state =
                bytes
                    |> List.take cSTATE_SIZE
                    |> toBytes
                    |> base64

            mCodeVerifier =
                bytes
                    |> List.drop cSTATE_SIZE
                    |> toBytes
                    |> OAuth.codeVerifierFromBytes
        in
        Maybe.map (\codeVerifier -> { state = state, codeVerifier = codeVerifier }) mCodeVerifier


calculateExpiryTime : Time.Posix -> Maybe Int -> Maybe Int
calculateExpiryTime now expiresIn =
    expiresIn
        |> Maybe.map
            (\seconds ->
                (Time.posixToMillis now // 1000) + seconds
            )


oauthErrorToString : { error : OAuth.ErrorCode, errorDescription : Maybe String } -> String
oauthErrorToString { error, errorDescription } =
    let
        desc =
            errorDescription |> Maybe.withDefault "" |> String.replace "+" " "
    in
    OAuth.errorCodeToString error ++ ": " ++ desc


shouldRefreshAccessToken : Time.Posix -> Configuration -> Oidc.Model.AuthData -> Bool
shouldRefreshAccessToken now config authData =
    case authData.expiresAt of
        Just expiresAt ->
            Time.posixToMillis expiresAt - Time.posixToMillis now <= config.refreshThresholdSeconds * 1000

        _ ->
            False
