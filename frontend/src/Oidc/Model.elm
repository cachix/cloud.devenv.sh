module Oidc.Model exposing
    ( AuthData
    , Configuration
    , Error(..)
    , Flow(..)
    , Model
    , UserInfo
    , authDataDecoder
    , authDataFromAuthenticationSuccess
    , encodeAuthData
    , encodeUserInfo
    , userInfoDecoder
    )

import Dict
import Json.Decode as Decode
import Json.Decode.Pipeline as Decode
import Json.Encode as Encode
import OAuth
import OAuth.AuthorizationCode.PKCE as OAuth
import Time
import Url exposing (Protocol(..), Url)


type alias Model =
    { flow : Flow
    , userInfo : Maybe UserInfo
    , configuration : Configuration
    , redirectUri : Url
    }


type Flow
    = NotAuthenticated
    | Authenticating OAuth.AuthorizationCode OAuth.CodeVerifier
    | Authenticated AuthData
    | Failed Error


type Error
    = ErrStateMismatch
    | ErrFailedToConvertBytes
    | ErrAuthorization OAuth.AuthorizationError
    | ErrAuthentication OAuth.AuthenticationError
    | ErrHTTPGetAccessToken
    | ErrHTTPGetUserInfo


type alias Configuration =
    { authorizationEndpoint : Url
    , tokenEndpoint : Url
    , userInfoEndpoint : Url
    , clientId : String
    , scope : List String
    , refreshThresholdSeconds : Int
    }


{-| The result of a successful authentication flow.
-}
type alias AuthData =
    { -- | An access token.
      token : OAuth.Token

    -- | An optional timestamp denoting the expiry of the `token`.
    , expiresAt : Maybe Time.Posix

    -- | An optional refresh token to allow requesting a fresh `AuthData` before or after the token expires.
    --
    -- The refresh token has its own expiry that is not communicated to the client.
    -- Clients should be prepared to trigger the auth flow if the token cannot be refresh for whatever reason.
    , refreshToken : Maybe OAuth.Token
    }


authDataFromAuthenticationSuccess : Time.Posix -> OAuth.AuthenticationSuccess -> AuthData
authDataFromAuthenticationSuccess now success =
    let
        addSecondsToPosix timestamp seconds =
            Time.millisToPosix (Time.posixToMillis timestamp + seconds * 1000)

        expiresAt =
            success.expiresIn
                |> Maybe.map (\seconds -> addSecondsToPosix now seconds)
    in
    { token = success.token
    , expiresAt = expiresAt
    , refreshToken = success.refreshToken
    }


{-| The user info returned by the OIDC provider.
-}
type alias UserInfo =
    { sub : String
    , name : Maybe String
    , given_name : Maybe String
    , family_name : Maybe String
    , locale : Maybe String
    , preferred_username : Maybe String
    , updated_at : Maybe Int
    , email : Maybe String
    , email_verified : Maybe Bool
    , beta_access : Bool
    }



--
-- DECODERS
--


authDataDecoder : Decode.Decoder AuthData
authDataDecoder =
    let
        decodeToken =
            Decode.string
                |> Decode.andThen
                    (\t ->
                        case OAuth.tokenFromString t of
                            Nothing ->
                                Decode.fail "Failed to decode token"

                            Just token ->
                                Decode.succeed token
                    )
    in
    Decode.succeed AuthData
        |> Decode.required "token" decodeToken
        |> Decode.optional "expiresAt" (Decode.nullable (Decode.int |> Decode.map Time.millisToPosix)) Nothing
        |> Decode.optional "refreshToken" (Decode.nullable decodeToken) Nothing


{-| {
"sub": "298937983627715588",
"name": "hey@sandydoo.me",
"given\_name": "Sander",
"family\_name": "Melnikov",
"locale": "en",
"updated\_at": 1734676923,
"preferred\_username": "sandydoo",
"email": "hey@sandydoo.me",
"email\_verified": true
}
-}
userInfoDecoder : Decode.Decoder UserInfo
userInfoDecoder =
    Decode.succeed UserInfo
        |> Decode.required "sub" Decode.string
        |> Decode.required "name" (Decode.nullable Decode.string)
        |> Decode.required "given_name" (Decode.nullable Decode.string)
        |> Decode.required "family_name" (Decode.nullable Decode.string)
        |> Decode.required "locale" (Decode.nullable Decode.string)
        |> Decode.required "preferred_username" (Decode.nullable Decode.string)
        |> Decode.required "updated_at" (Decode.nullable Decode.int)
        |> Decode.optional "email" (Decode.nullable Decode.string) Nothing
        |> Decode.optional "email_verified" (Decode.nullable Decode.bool) Nothing
        |> Decode.custom betaAccessDecoder


{-| Decoder for beta\_access that checks both:

1.  Direct "beta\_access" field
2.  "<urn:zitadel:iam:org:project:roles"> for "beta\_user" role

-}
betaAccessDecoder : Decode.Decoder Bool
betaAccessDecoder =
    Decode.oneOf
        [ -- Try direct beta_access field first
          Decode.field "beta_access" Decode.bool
        , -- Then check for beta_user role in Zitadel roles
          Decode.field "urn:zitadel:iam:org:project:roles" hasBetaUserRole
        , -- Default to False if neither exists
          Decode.succeed False
        ]


{-| Check if the roles object contains "beta\_user" key
-}
hasBetaUserRole : Decode.Decoder Bool
hasBetaUserRole =
    Decode.dict Decode.value
        |> Decode.map (\roles -> Dict.member "beta_user" roles)



--
-- ENCODERS
--


encodeMaybe : (a -> Encode.Value) -> Encode.Value -> Maybe a -> Encode.Value
encodeMaybe f d v =
    Maybe.map f v |> Maybe.withDefault d


encodeNullable : (a -> Encode.Value) -> Maybe a -> Encode.Value
encodeNullable f v =
    encodeMaybe f Encode.null v


encodeAuthData : AuthData -> Encode.Value
encodeAuthData o =
    Encode.object
        [ ( "token", Encode.string (OAuth.tokenToString o.token) )
        , ( "refreshToken", encodeNullable (OAuth.tokenToString >> Encode.string) o.refreshToken )
        , ( "expiresAt", encodeNullable (Time.posixToMillis >> Encode.int) o.expiresAt )
        ]


encodeUserInfo : UserInfo -> Encode.Value
encodeUserInfo o =
    Encode.object
        [ ( "sub", Encode.string o.sub )
        , ( "name", encodeNullable Encode.string o.name )
        , ( "given_name", encodeNullable Encode.string o.given_name )
        , ( "family_name", encodeNullable Encode.string o.family_name )
        , ( "locale", encodeNullable Encode.string o.locale )
        , ( "preferred_username", encodeNullable Encode.string o.preferred_username )
        , ( "updated_at", encodeNullable Encode.int o.updated_at )
        , ( "email", encodeNullable Encode.string o.email )
        , ( "email_verified", encodeNullable Encode.bool o.email_verified )
        , ( "beta_access", Encode.bool o.beta_access )
        ]
