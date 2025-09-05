module Pages.Waitlist exposing (Model, Msg, page)

import Auth
import Components.LandingLayout
import Effect exposing (Effect)
import Html
import Html.Attributes
import Page exposing (Page)
import Route exposing (Route)
import Route.Path
import Shared
import View exposing (View)


page : Auth.User -> Shared.Model -> Route () -> Page Model Msg
page user shared route =
    Page.new
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view user shared route
        }



-- INIT


type alias Model =
    {}


init : () -> ( Model, Effect Msg )
init _ =
    ( {}
    , Effect.none
    )



-- UPDATE


type Msg
    = SignIn
    | ToggleTheme


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SignIn ->
            ( model
            , Effect.signIn
            )

        ToggleTheme ->
            ( model
            , Effect.toggleTheme
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


view : Auth.User -> Shared.Model -> Route () -> Model -> View Msg
view user shared route model =
    { title = "Welcome to the Waitlist - DevEnv"
    , body =
        [ Components.LandingLayout.view
            { onSignIn = SignIn
            , onToggleTheme = ToggleTheme
            , theme = shared.theme
            , user = shared.user
            , route = route
            }
            [ Html.div
                [ Html.Attributes.class "container max-w-4xl mx-auto px-4 py-16" ]
                [ Html.div
                    [ Html.Attributes.class "space-y-12" ]
                    [ Html.div
                        [ Html.Attributes.class "bg-gradient-to-r from-green-50 to-blue-50 dark:from-green-900/20 dark:to-blue-900/20 rounded-2xl px-8 py-18 border border-green-100 dark:border-green-800/30 shadow-lg" ]
                        [ Html.div
                            [ Html.Attributes.class "flex items-start space-x-4" ]
                            [ Html.div
                                [ Html.Attributes.class "flex-shrink-0 h-10 w-10 flex items-center justify-center rounded-full bg-green-100 dark:bg-green-800/30 shadow-sm" ]
                                [ Html.span
                                    [ Html.Attributes.class "text-green-600 dark:text-green-400 font-bold text-lg" ]
                                    [ Html.text "✓" ]
                                ]
                            , Html.div
                                [ Html.Attributes.class "flex-1" ]
                                [ Html.h2
                                    [ Html.Attributes.class "text-4xl font-extrabold text-gray-900 dark:text-dark-text" ]
                                    [ Html.text "Thank you for joining!" ]
                                , Html.p
                                    [ Html.Attributes.class "mt-2 text-lg text-gray-600 dark:text-dark-text-secondary" ]
                                    [ Html.text "You've been added to our waitlist" ]
                                ]
                            ]
                        ]
                    , Html.div
                        [ Html.Attributes.class "grid md:grid-cols-2 gap-8" ]
                        [ Html.div
                            [ Html.Attributes.class "p-6" ]
                            [ Html.h3
                                [ Html.Attributes.class "text-xl font-semibold text-gray-900 dark:text-dark-text mb-4" ]
                                [ Html.text "Private Beta" ]
                            , Html.div [ Html.Attributes.class "space-y-3" ]
                                [ Html.p
                                    [ Html.Attributes.class "text-sm text-gray-600 dark:text-dark-text-secondary leading-relaxed" ]
                                    [ Html.text "Devenv Cloud is currently in private beta. We're carefully rolling out access to ensure the best possible experience for everyone." ]
                                , Html.p
                                    [ Html.Attributes.class "text-sm text-gray-700 dark:text-gray-400 font-medium" ]
                                    [ Html.text "We'll notify you via email when your invite is ready." ]
                                ]
                            ]
                        , Html.div
                            [ Html.Attributes.class "p-6" ]
                            [ Html.h3
                                [ Html.Attributes.class "text-xl font-semibold text-gray-900 dark:text-dark-text mb-4" ]
                                [ Html.text "In the meantime" ]
                            , Html.div
                                [ Html.Attributes.class "space-y-4" ]
                                [ Html.a
                                    [ Html.Attributes.href "https://devenv.sh"
                                    , Html.Attributes.target "_blank"
                                    , Html.Attributes.class "block text-sm text-gray-600 dark:text-dark-text-secondary hover:underline hover:text-gray-800 dark:hover:text-dark-text transition-colors"
                                    ]
                                    [ Html.text "Get started with Devenv locally → " ]
                                , Html.a
                                    [ Route.Path.href Route.Path.Home
                                    , Html.Attributes.class "block text-sm text-gray-600 dark:text-dark-text-secondary hover:underline hover:text-gray-800 dark:hover:text-dark-text transition-colors"
                                    ]
                                    [ Html.text "Learn more about Devenv Cloud →" ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    }
