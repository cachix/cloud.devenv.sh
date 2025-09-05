module Components.Button exposing
    ( Action(..)
    , Button
    , Size(..)
    , Variant(..)
    , asDanger
    , asGhost
    , asLarge
    , asSecondary
    , asSmall
    , asSuccess
    , new
    , view
    , withAttributes
    , withDisabled
    , withLoadingResponse
    , withSize
    , withTooltip
    , withVariant
    )

import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Events.Extra exposing (..)
import RemoteData exposing (RemoteData)
import Route.Path
import Svg
import Svg.Attributes


type Action msg
    = Route Route.Path.Path
    | Href String
    | Click msg


type Variant
    = Primary
    | Secondary
    | Success
    | Danger
    | Ghost


type Size
    = Small
    | Medium
    | Large


type Button msg
    = Button
        { label : String
        , action : Action msg
        , icon : Maybe (List (Svg.Attribute msg) -> Html msg)
        , isDisabled : Bool
        , variant : Variant
        , size : Size
        , attrs : List (Attribute msg)
        , tooltip : Maybe String
        }


new :
    { label : String
    , action : Action msg
    , icon : Maybe (List (Svg.Attribute msg) -> Html msg)
    }
    -> Button msg
new props =
    Button
        { label = props.label
        , action = props.action
        , icon = props.icon
        , isDisabled = False
        , variant = Primary
        , size = Medium
        , attrs = []
        , tooltip = Nothing
        }


withLoadingResponse : RemoteData.WebData a -> Button msg -> Button msg
withLoadingResponse response (Button settings) =
    Button { settings | isDisabled = RemoteData.isLoading response }


withDisabled : Bool -> Button msg -> Button msg
withDisabled isDisabled (Button settings) =
    Button { settings | isDisabled = isDisabled }


withTooltip : String -> Button msg -> Button msg
withTooltip tooltipText (Button settings) =
    Button { settings | tooltip = Just tooltipText }


withAttributes : List (Attribute msg) -> Button msg -> Button msg
withAttributes attributes (Button settings) =
    Button { settings | attrs = attributes ++ settings.attrs }


withVariant : Variant -> Button msg -> Button msg
withVariant variant (Button settings) =
    Button { settings | variant = variant }


withSize : Size -> Button msg -> Button msg
withSize size (Button settings) =
    Button { settings | size = size }


asSecondary : Button msg -> Button msg
asSecondary =
    withVariant Secondary


asSuccess : Button msg -> Button msg
asSuccess =
    withVariant Success


asDanger : Button msg -> Button msg
asDanger =
    withVariant Danger


asGhost : Button msg -> Button msg
asGhost =
    withVariant Ghost


asSmall : Button msg -> Button msg
asSmall =
    withSize Small


asLarge : Button msg -> Button msg
asLarge =
    withSize Large


view : Button msg -> Html msg
view (Button settings) =
    let
        elementType =
            case settings.action of
                Route _ ->
                    a

                Href _ ->
                    a

                Click _ ->
                    button

        actionAttrs =
            if settings.isDisabled then
                [ title (Maybe.withDefault "Button disabled" settings.tooltip) ]

            else
                [ case settings.action of
                    Route path ->
                        Route.Path.href path

                    Href link ->
                        href link

                    Click msg ->
                        onClickPreventDefaultAndStopPropagation msg
                , title (Maybe.withDefault "" settings.tooltip)
                ]

        buttonClasses =
            [ class "rounded-sm font-medium inline-flex items-center justify-center focus:outline-hidden focus:ring-1 focus:ring-offset-1 duration-200 shadow-none hover:shadow-xs"
            , class (sizeClass settings.size)
            , classList
                [ ( variantClass settings.variant, True )
                , ( "opacity-60 cursor-not-allowed", settings.isDisabled )
                ]
            ]

        iconElement =
            case settings.icon of
                Just icon ->
                    span [ class "inline-flex mr-2" ]
                        [ icon [ Svg.Attributes.class "w-5 h-5" ] ]

                Nothing ->
                    text ""
    in
    elementType
        (buttonClasses ++ actionAttrs ++ settings.attrs)
        [ iconElement
        , text settings.label
        ]


sizeClass : Size -> String
sizeClass size =
    case size of
        Small ->
            "py-1 px-3 text-sm"

        Medium ->
            "py-1 px-2 text-base"

        Large ->
            "py-3 px-6 text-lg"


variantClass : Variant -> String
variantClass variant =
    case variant of
        Primary ->
            "bg-surface hover:bg-gray-100 hover:text-primary text-theme focus:ring-primary border border-theme/20"

        Secondary ->
            "bg-surface hover:bg-gray-100 hover:text-primary text-theme-secondary focus:ring-gray-500 border border-theme-secondary/20"

        Success ->
            "bg-surface hover:bg-gray-100 text-status-success focus:ring-status-success border border-status-success/20"

        Danger ->
            "bg-surface hover:bg-gray-100 text-status-error focus:ring-status-error border border-status-error/20"

        Ghost ->
            "bg-transparent hover:bg-gray-100 hover:text-primary text-theme focus:ring-border border border-theme"
