module Pages.NotFound_ exposing (Model, Msg, page)

import Components.Button as Button
import Effect exposing (Effect)
import Html exposing (..)
import Html.Attributes exposing (..)
import Icons
import Page exposing (Page)
import Route exposing (Route)
import Route.Path
import Shared
import View exposing (View)


page : Shared.Model -> Route () -> Page Model Msg
page shared route =
    Page.new
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view
        }



-- INIT


type alias Model =
    {}


init : () -> ( Model, Effect Msg )
init () =
    ( {}
    , Effect.none
    )



-- UPDATE


type Msg
    = NoOp


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        NoOp ->
            ( model
            , Effect.none
            )



-- SUBSCRIPTIONS


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


view : Model -> View Msg
view model =
    { title = "Page Not Found - Devenv Cloud"
    , body =
        [ div [ class "min-h-screen flex items-center justify-center bg-gray-50 dark:bg-gray-900 px-4" ]
            [ div [ class "max-w-md text-center" ]
                [ div [ class "mb-8" ]
                    [ div [ class "text-9xl font-bold text-gray-300 dark:text-gray-700 mb-4" ]
                        [ text "404" ]
                    , h1 [ class "text-2xl md:text-3xl font-bold text-gray-900 dark:text-white mb-4" ]
                        [ text "Page Not Found" ]
                    , p [ class "text-gray-600 dark:text-gray-400 mb-8" ]
                        [ text "Sorry, we couldn't find the page you're looking for." ]
                    ]
                , Button.new
                    { label = "Go back"
                    , action = Button.Route Route.Path.Home_
                    , icon = Just Icons.arrowLeft
                    }
                    |> Button.view
                ]
            ]
        ]
    }
