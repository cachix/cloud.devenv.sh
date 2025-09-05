module Components.Dropdown exposing
    ( dropdown, viewItem
    , iconButtonStyle, standardDropdownStyle
    )

{-| A reusable dropdown component with a toggle button and a dropdown menu.


# Core Components

@docs dropdown, viewItem


# Styling Helpers

@docs iconButtonStyle, standardDropdownStyle

-}

import Dropdown
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (stopPropagationOn)
import Json.Decode as Decode


{-| Create a dropdown using the external Dropdown library.
This function wraps the external library to provide a consistent API.
-}
dropdown :
    { identifier : String
    , toggleButton : Html msg
    , toggleButtonClass : String
    , items : List (Html msg)
    , onToggle : Bool -> msg
    , isOpen : Bool
    }
    -> Html msg
dropdown config =
    Dropdown.dropdown
        { identifier = config.identifier
        , toggleEvent = Dropdown.OnClick
        , drawerVisibleAttribute = class "visible"
        , onToggle = config.onToggle
        , layout =
            \{ toDropdown, toToggle, toDrawer } ->
                toDropdown div
                    [ class "relative inline-block text-left" ]
                    [ toToggle button
                        [ class config.toggleButtonClass
                        , attribute "type" "button"
                        , attribute "id" (config.identifier ++ "-button")
                        , attribute "aria-expanded"
                            (if config.isOpen then
                                "true"

                             else
                                "false"
                            )
                        , attribute "aria-haspopup" "true"
                        , attribute "aria-controls" (config.identifier ++ "-menu")
                        ]
                        [ config.toggleButton ]
                    , toDrawer div
                        [ class "absolute right-0 top-full z-50 mt-1 min-w-32 py-1 rounded-lg border border-red dark:border-dark-border shadow-lg bg-white dark:bg-dark-surface text-xs focus:outline-hidden transition-all duration-100 ease-in-out origin-top-right"
                        , attribute "role" "menu"
                        , attribute "aria-orientation" "vertical"
                        , attribute "aria-labelledby" (config.identifier ++ "-button")
                        , attribute "id" (config.identifier ++ "-menu")
                        , if not config.isOpen then
                            attribute "hidden" ""

                          else
                            class ""
                        ]
                        config.items
                    ]
        , isToggled = config.isOpen
        }


{-| Helper function to create a dropdown menu item.
-}
viewItem :
    { onClick : msg
    , icon : Maybe (Html msg)
    , label : String
    , isDanger : Bool
    , tooltip : Maybe String -- Optional tooltip text
    }
    -> Html msg
viewItem config =
    let
        baseClass =
            "block w-full text-left px-3 py-1.5 text-xs cursor-pointer transition-colors duration-150"

        textColor =
            if config.isDanger then
                "text-red-600 dark:text-red-400 hover:bg-gray-100 dark:hover:bg-dark-surface/50 hover:text-red-700 dark:hover:text-red-300"

            else
                "app-link hover:bg-gray-100 dark:hover:bg-dark-surface/50"

        -- Add tooltip attributes if provided
        tooltipAttrs =
            case config.tooltip of
                Just tooltipText ->
                    [ title tooltipText
                    , attribute "aria-label" tooltipText
                    ]

                Nothing ->
                    []
    in
    button
        ([ class (baseClass ++ " " ++ textColor)
         , Html.Events.stopPropagationOn "click" (Decode.succeed ( config.onClick, True ))
         , attribute "role" "menuitem"
         , tabindex -1
         ]
            ++ tooltipAttrs
        )
        [ div [ class "flex items-center gap-2" ]
            [ case config.icon of
                Just icon ->
                    icon

                Nothing ->
                    text ""
            , text config.label
            ]
        ]


{-| A standardized style for icon-based dropdown toggle buttons
-}
iconButtonStyle : String
iconButtonStyle =
    "p-1 rounded-full hover:bg-light/50 dark:hover:bg-dark-surface/50 hover:text-primary dark:hover:text-primary transition-colors cursor-pointer focus:outline-hidden focus:ring-2 focus:ring-indigo-500 dark:focus:ring-indigo-400"


{-| A standardized style for account/user dropdown toggles
-}
standardDropdownStyle : String
standardDropdownStyle =
    "inline-flex justify-center w-full items-center rounded-md border border-light dark:border-dark-border px-4 py-2 bg-white dark:bg-dark-surface text-sm font-medium text-dark dark:text-dark-text hover:bg-light dark:hover:bg-dark-border focus:outline-hidden focus:ring-2 focus:ring-indigo-500 dark:focus:ring-indigo-400 relative"
