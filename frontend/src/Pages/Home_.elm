module Pages.Home_ exposing (Model, Msg, page)

import Components.LandingLayout
import Dict
import Effect exposing (Effect)
import Html exposing (..)
import Html.Attributes exposing (..)
import Page exposing (Page)
import Pages.Home exposing (viewLanding)
import RemoteData
import Route exposing (Route)
import Route.Path
import Shared
import Shared.Model
import View exposing (View)


page : Shared.Model -> Route () -> Page Model Msg
page shared route =
    Page.new
        { init = init shared
        , update = update route
        , subscriptions = subscriptions shared
        , view = view shared route
        }


type alias Model =
    {}


init : Shared.Model -> () -> ( Model, Effect Msg )
init shared _ =
    case shared.user of
        RemoteData.Success userInfo ->
            -- Redirect authenticated users to their dashboard
            case userInfo.preferred_username of
                Just username ->
                    ( {}
                    , Effect.replaceRoute
                        { path = Route.Path.Github_Owner_ { owner = username }
                        , query = Dict.empty
                        , hash = Nothing
                        }
                    )

                Nothing ->
                    -- Fallback if no username
                    ( {}, Effect.none )

        _ ->
            -- Show landing page for guests and loading states
            ( {}, Effect.none )


type Msg
    = SignIn
    | ToggleTheme


update : Route () -> Msg -> Model -> ( Model, Effect Msg )
update route msg model =
    case msg of
        SignIn ->
            ( model
            , Effect.signIn
            )

        ToggleTheme ->
            ( model
            , Effect.toggleTheme
            )


subscriptions : Shared.Model -> Model -> Sub Msg
subscriptions shared model =
    Sub.none


view : Shared.Model -> Route () -> Model -> View Msg
view shared route model =
    { title = "Devenv Cloud - CI for Nix"
    , body =
        [ Components.LandingLayout.view
            { onSignIn = SignIn
            , onToggleTheme = ToggleTheme
            , theme = shared.theme
            , user = shared.user
            , route = route
            }
            [ viewLanding SignIn ]
        ]
    }
