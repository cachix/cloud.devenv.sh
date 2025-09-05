module Components.Label exposing
    ( Label
    , Size(..)
    , Type
    , asCombined
    , asDanger
    , asInfo
    , asLarge
    , asLink
    , asSmall
    , asSuccess
    , asWarning
    , new
    , view
    , withAttributes
    , withClass
    , withCombined
    , withHref
    , withIcon
    , withType
    )

{-| Reusable label component with consistent styling.
-}

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)


type Type msg
    = Default
    | Success
    | Warning
    | Danger
    | Info
    | Combined (List (Label msg))


type Size
    = Small
    | Medium
    | Large


type Label msg
    = Label
        { text : String
        , type_ : Type msg
        , size : Size
        , customClass : Maybe String
        , attrs : List (Attribute msg)
        , href : Maybe String
        , icon : Maybe (Html msg)
        }


new : { text : String } -> Label msg
new props =
    Label
        { text = props.text
        , type_ = Default
        , size = Medium
        , customClass = Nothing
        , attrs = []
        , href = Nothing
        , icon = Nothing
        }


withType : Type msg -> Label msg -> Label msg
withType type_ (Label settings) =
    Label { settings | type_ = type_ }


withCombined : List (Label msg) -> Label msg -> Label msg
withCombined labels (Label settings) =
    Label { settings | type_ = Combined labels }


withClass : String -> Label msg -> Label msg
withClass customClass (Label settings) =
    Label { settings | customClass = Just customClass }


withAttributes : List (Attribute msg) -> Label msg -> Label msg
withAttributes attributes (Label settings) =
    Label { settings | attrs = attributes ++ settings.attrs }


withHref : String -> Label msg -> Label msg
withHref link (Label settings) =
    Label { settings | href = Just link }


asCombined : List (Label msg) -> Label msg -> Label msg
asCombined =
    withCombined


asSuccess : Label msg -> Label msg
asSuccess =
    withType Success


asWarning : Label msg -> Label msg
asWarning =
    withType Warning


asDanger : Label msg -> Label msg
asDanger =
    withType Danger


asInfo : Label msg -> Label msg
asInfo =
    withType Info


asSmall : Label msg -> Label msg
asSmall (Label settings) =
    Label { settings | size = Small }


asLarge : Label msg -> Label msg
asLarge (Label settings) =
    Label { settings | size = Large }


asLink : String -> Label msg -> Label msg
asLink =
    withHref


withIcon : Html msg -> Label msg -> Label msg
withIcon icon (Label settings) =
    Label { settings | icon = Just icon }


view : Label msg -> Html msg
view (Label settings) =
    case settings.type_ of
        Combined labels ->
            div [ class "flex items-center" ]
                (List.map viewSingleLabel labels)

        _ ->
            viewSingleLabel (Label settings)


viewSingleLabel : Label msg -> Html msg
viewSingleLabel (Label settings) =
    let
        elementType =
            case settings.href of
                Just _ ->
                    a

                Nothing ->
                    span

        hrefAttr =
            case settings.href of
                Just link ->
                    [ href link ]

                Nothing ->
                    []

        baseClasses =
            "inline-flex items-center justify-center font-mono text-xs px-2 py-1"

        ( typeClasses, roundedClasses ) =
            case settings.type_ of
                Default ->
                    ( "text-gray-800 dark:text-dark-text bg-gray-200 dark:bg-dark-surface", "rounded-sm" )

                Success ->
                    ( "bg-green-100 dark:bg-green-900/30 text-green-800 dark:text-green-300", "rounded-sm" )

                Warning ->
                    ( "bg-yellow-100 dark:bg-yellow-900/30 text-yellow-800 dark:text-yellow-300", "rounded-sm" )

                Danger ->
                    ( "bg-red-100 dark:bg-red-900/30 text-red-800 dark:text-red-300", "rounded-sm" )

                Info ->
                    ( "bg-blue-500 dark:bg-blue-700 text-white dark:text-white", "rounded-sm" )

                Combined _ ->
                    ( "", "" )

        sizeClass =
            case settings.size of
                Small ->
                    "text-xs"

                Medium ->
                    "text-sm"

                Large ->
                    "text-base"

        customClassAttr =
            case settings.customClass of
                Just custom ->
                    [ class custom ]

                Nothing ->
                    []

        allClasses =
            String.join " " [ baseClasses, typeClasses, roundedClasses, sizeClass ]
    in
    elementType
        ([ class allClasses ] ++ customClassAttr ++ hrefAttr ++ settings.attrs)
        (case settings.icon of
            Just icon ->
                if String.isEmpty settings.text then
                    [ span [ class "inline-flex items-center" ] [ icon ] ]

                else
                    [ span [ class "inline-flex items-center mr-1" ] [ icon ]
                    , text settings.text
                    ]

            Nothing ->
                [ text settings.text ]
        )


{-| Creates a rev@branch label, properly styled and linked to GitHub
-}
viewRevBranch : { rev : String, ref : String, owner : String, repo : String } -> Html msg
viewRevBranch { rev, ref, owner, repo } =
    view
        (new { text = "" }
            |> asCombined
                [ new { text = String.left 7 rev }
                    |> asLink ("https://github.com/" ++ owner ++ "/" ++ repo ++ "/commit/" ++ rev)
                    |> withClass "rounded-l"
                , new { text = "@" }
                    |> withClass "px-0"
                , new { text = ref }
                    |> asLink ("https://github.com/" ++ owner ++ "/" ++ repo ++ "/tree/" ++ ref)
                    |> withClass "rounded-r"
                ]
        )
