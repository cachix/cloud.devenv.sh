module Components.GitHub exposing
    ( getAvatarUrl
    , viewAvatar
    )

{-| GitHub component utilities for consistent rendering of GitHub-related elements.
-}

import Html exposing (..)
import Html.Attributes exposing (..)


{-| Get the GitHub avatar URL for a username
-}
getAvatarUrl : String -> String
getAvatarUrl username =
    "https://github.com/" ++ username ++ ".png"


{-| Renders a GitHub avatar with consistent styling.
-}
viewAvatar : { username : String, size : String, extraClasses : String } -> Html msg
viewAvatar { username, size, extraClasses } =
    let
        sizeClass =
            case size of
                "xs" ->
                    "w-4 h-4"

                "sm" ->
                    "w-6 h-6"

                "md" ->
                    "w-8 h-8"

                "lg" ->
                    "w-10 h-10"

                _ ->
                    "w-8 h-8"

        classes =
            sizeClass ++ " rounded-full " ++ extraClasses
    in
    img
        [ src (getAvatarUrl username)
        , class classes
        , alt ("Avatar for " ++ username)
        ]
        []
