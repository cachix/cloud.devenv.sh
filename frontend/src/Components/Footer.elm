module Components.Footer exposing (view)

import Html exposing (..)
import Html.Attributes exposing (..)
import Icons
import Svg.Attributes


discordUrl : String
discordUrl =
    "https://discord.gg/naMgvexb6q"


view : Html msg
view =
    let
        mk title links =
            div []
                [ h2 [ class "font-semibold text-theme" ] [ text title ]
                , ul [ class "mt-3 space-y-2" ]
                    (List.map
                        (\( name, url, external ) ->
                            li []
                                [ a
                                    [ href url
                                    , class "app-link"
                                    , if external then
                                        target "_blank"

                                      else
                                        class ""
                                    ]
                                    [ text name ]
                                ]
                        )
                        links
                    )
                ]
    in
    footer
        [ class "mt-12 bg-surface border-t border-theme" ]
        [ div
            [ class "container justify-self-end text-sm py-18 leading-6 grid gap-6 grid-cols-2 md:grid-cols-4 max-w-4xl mx-auto px-4" ]
            [ mk "Getting Started"
                [ ( "Start with devenv", "https://devenv.sh/getting-started/", True )
                ]
            , mk "Resources"
                [ ( "GitHub", "https://github.com/cachix/cloud.devenv.sh", True )
                , ( "Community", discordUrl, True )
                ]
            , mk "Our Products"
                [ ( "Cachix", "https://cachix.org", True )
                , ( "Devenv", "https://devenv.sh", True )
                , ( "Devenv Cloud", "https://cloud.devenv.sh", False )
                ]
            ]
        , div
            [ class "py-4 bg-surface" ]
            [ div
                [ class "container max-w-4xl mx-auto px-4 flex justify-between items-center" ]
                [ div [ class "text-xs text-theme" ]
                    [ text "© 2025 Cachix. All rights reserved." ]
                , div [ class "flex items-center space-x-4" ]
                    [ a [ href "https://github.com/cachix", target "_blank", class "app-link" ]
                        [ Icons.github [ Svg.Attributes.class "w-5 h-5" ] ]
                    , a [ href discordUrl, target "_blank", class "app-link" ]
                        [ Icons.discord [ Svg.Attributes.class "w-5 h-5" ] ]
                    ]
                ]
            ]
        ]
