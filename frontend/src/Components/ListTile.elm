module Components.ListTile exposing (ListTile, new, view, withHeader, withRows)

import Html exposing (..)
import Html.Attributes exposing (..)


type alias ListTile msg =
    { header : Maybe (Html msg)
    , rows : List (Html msg)
    }


new : ListTile msg
new =
    { header = Nothing
    , rows = []
    }


withHeader : Html msg -> ListTile msg -> ListTile msg
withHeader content model =
    { model | header = Just content }


withRows : List (Html msg) -> ListTile msg -> ListTile msg
withRows rows model =
    { model | rows = rows }


view : ListTile msg -> Html msg
view model =
    div [ class "bg-white dark:bg-dark-surface border border-gray-200 dark:border-dark-border rounded-xl shadow-xs hover:shadow-md dark:hover:shadow-xl dark:hover:shadow-black/10 transition-all duration-200" ]
        [ case model.header of
            Just header ->
                div [ class "bg-gray-50 dark:bg-gray-900/50 border-b border-gray-200 dark:border-dark-border px-5 py-4 rounded-t-xl" ]
                    [ header ]

            Nothing ->
                text ""
        , div [ class "divide-y divide-gray-100 dark:divide-dark-border" ]
            model.rows
        ]
