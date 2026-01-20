module Components.LandingLayout exposing (view)

import Components.Button
import Components.Footer
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Http
import Icons
import RemoteData
import Route exposing (Route)
import Route.Path
import Shared.Model exposing (Theme(..), User)
import Svg.Attributes


type alias Props msg =
    { onSignIn : msg
    , onToggleTheme : msg
    , theme : Theme
    , user : RemoteData.RemoteData Http.Error User
    , route : Route ()
    }


view : Props msg -> List (Html msg) -> Html msg
view props content =
    Html.div
        [ class "theme-map page min-h-screen flex flex-col dark:bg-dark-bg" ]
        [ viewHeader props
        , div [ class "grow" ] content
        , Components.Footer.view
        ]


viewHeader : Props msg -> Html msg
viewHeader { onSignIn, onToggleTheme, theme, user, route } =
    let
        themeToggleButton =
            button
                [ class "p-2 text-secondary dark:text-dark-text-secondary rounded-full hover:text-primary dark:hover:text-primary focus:outline-hidden transition-colors ml-2"
                , onClick onToggleTheme
                ]
                [ if theme == Dark then
                    Icons.sunIcon [ Svg.Attributes.class "w-5 h-5" ]

                  else
                    Icons.moonIcon [ Svg.Attributes.class "w-5 h-5" ]
                ]

        headerButtons =
            -- On /home page, check if user is actually authenticated
            case user of
                RemoteData.Success userInfo ->
                    let
                        ( label, link ) =
                            case route.path of
                                Route.Path.Waitlist ->
                                    ( "cloud.devenv.sh", Route.Path.Home )

                                _ ->
                                    ( if userInfo.betaAccess then
                                        "Go to dashboard"

                                      else
                                        "Go to waitlist"
                                    , Route.Path.Home_
                                    )
                    in
                    -- Show "Go to Dashboard" button for authenticated users
                    div [ class "flex gap-2" ]
                        [ Components.Button.new
                            { label = label
                            , icon = Nothing
                            , action = Components.Button.Href (Route.Path.toString link)
                            }
                            |> Components.Button.view
                        ]

                _ ->
                    -- Show login buttons for logged-out users
                    div [] []

        {-
           div [ class "flex gap-4" ]
               [ Components.Button.new
                   { label = "Log in"
                   , icon = Nothing
                   , action = Components.Button.Click onSignIn
                   }
                   |> Components.Button.view
               , Components.Button.new
                   { label = "Sign up"
                   , icon = Nothing
                   , action = Components.Button.Click onSignIn
                   }
                   |> Components.Button.view
               ]
        -}
    in
    nav
        [ class "container max-w-4xl p-4 text-secondary font-semibold flex flex-wrap items-center justify-between mx-auto dark:text-dark-text-secondary"
        ]
        [ div
            [ class "items-center flex justify-between mx-auto w-full"
            ]
            [ a [ class "flex h-8", Route.Path.href Route.Path.Home_ ]
                [ img [ class "logo-light", src "/logo.webp" ] []
                , img [ class "logo-dark", src "/logo-dark.webp" ] []
                ]
            , div [ class "hidden md:flex items-center justify-end space-x-2" ]
                [ themeToggleButton
                , headerButtons
                ]
            , div [ class "md:hidden flex items-center space-x-2" ]
                [ themeToggleButton ]
            ]
        ]
