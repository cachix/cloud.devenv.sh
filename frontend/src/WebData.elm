module WebData exposing (..)

import Html exposing (..)
import Html.Attributes exposing (..)
import Http
import Icons
import RemoteData exposing (WebData)
import Svg.Attributes


toHtml : (a -> Html msg) -> WebData a -> Html msg
toHtml go data_ =
    case data_ of
        RemoteData.NotAsked ->
            text ""

        RemoteData.Loading ->
            div [ class "h-screen flex items-center justify-center" ]
                [ Icons.spinner [] ]

        RemoteData.Success value ->
            go value

        RemoteData.Failure error ->
            renderError (RemoteData.Failure error)


renderError : WebData a -> Html msg
renderError webdata =
    case webdata of
        RemoteData.Failure error ->
            let
                er =
                    errorToString error
            in
            div [ class "bg-red-600 text-white dark:bg-red-700 px-4 py-3 rounded-md shadow-md m-4 border border-red-700" ]
                [ div [ class "flex items-center" ]
                    [ Icons.exclamation [ Svg.Attributes.class "w-5 h-5 mr-2 text-white" ]
                    , p [ class "font-medium" ] [ text er ]
                    ]
                , if
                    case error of
                        Http.BadBody _ ->
                            True

                        _ ->
                            False
                  then
                    pre [ class "whitespace-pre-wrap mt-2 p-2 bg-red-800 rounded-sm text-xs overflow-auto max-h-64" ]
                        [ case error of
                            Http.BadBody body ->
                                text body

                            _ ->
                                text ""
                        ]

                  else
                    text ""
                ]

        _ ->
            text ""



-- TODO: roll our own Error


{-| Convert an HTTP error to a user-friendly string message
-}
errorToString : Http.Error -> String
errorToString error =
    case error of
        Http.BadStatus status ->
            "Bad status: " ++ String.fromInt status

        Http.BadBody b ->
            "Bad body: " ++ b

        Http.Timeout ->
            "Timeout"

        Http.NetworkError ->
            "Network error"

        Http.BadUrl url ->
            "Bad url: " ++ url
