module Components.LogViewer exposing (Model, Msg, init, subscriptions, update, view)

import Array exposing (Array)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import Html.Keyed as Keyed
import Html.Lazy as Lazy
import Icons
import Json.Decode as Decode
import Json.Encode as Encode
import Ports
import Svg.Attributes
import Task
import Term.ANSI as ANSI


type alias Model =
    { logs : Array LogLine
    , search : String
    , scrollPosition : Float
    , containerHeight : Float
    , selectedLine : Maybe Int
    , url : String
    , followTail : Bool
    , error : Maybe String
    , connectionId : String
    , filteredLogs : Array LogLine -- Simplified cache
    , needsRefilter : Bool -- Track when refiltering is needed
    , isReconnecting : Bool
    , showDebugLogs : Bool
    , jobId : String
    , isFullscreen : Bool
    }


type alias LogLine =
    { timestamp : String
    , message : String
    , level : String
    , line : Int
    }


type Msg
    = SetSearch String
    | SelectLine Int
    | ToggleFollowTail
    | SSEMessages Encode.Value -- Changed to handle batch messages
    | SSEError String
    | SSEConnected
    | ScrollToBottom
    | UserScrolled Bool -- True if at bottom, False if scrolled up
    | ScrollPositionChanged { scrollTop : Float, scrollHeight : Float, clientHeight : Float }
    | ToggleDebugLogs
    | ToggleFullscreen
    | FullscreenChanged Bool


init : String -> String -> String -> ( Model, Cmd Msg )
init connectionId url jobId =
    let
        model =
            { logs = Array.empty
            , search = ""
            , scrollPosition = 0
            , containerHeight = 600
            , selectedLine = Nothing
            , url = url
            , followTail = True
            , error = Nothing
            , connectionId = connectionId
            , filteredLogs = Array.empty
            , needsRefilter = False
            , isReconnecting = False
            , showDebugLogs = False
            , jobId = jobId
            , isFullscreen = False
            }
    in
    ( model
    , Cmd.batch
        [ Ports.connectSSE { id = connectionId, url = url }
        , Ports.setupScrollListener connectionId
        ]
    )


shouldShowLog : Bool -> LogLine -> Bool
shouldShowLog showDebugLogs logLine =
    if showDebugLogs then
        True

    else
        -- Show INFO, WARN, ERROR levels when debug mode is off
        case String.toUpper logLine.level of
            "DEBUG" ->
                False

            "TRACE" ->
                False

            _ ->
                True


matchesSearchTerm : String -> LogLine -> Bool
matchesSearchTerm search logLine =
    let
        searchTerm =
            String.toLower search
    in
    String.isEmpty searchTerm
        || String.contains searchTerm (String.toLower logLine.message)
        || String.contains searchTerm (String.toLower logLine.timestamp)


applyFilters : Model -> Array LogLine
applyFilters model =
    model.logs
        |> Array.filter (shouldShowLog model.showDebugLogs)
        |> Array.filter (matchesSearchTerm model.search)


update : Msg -> Model -> ( Model, Cmd Msg )
update msg model =
    case msg of
        SetSearch str ->
            let
                -- Reset scroll when search changes significantly
                shouldResetScroll =
                    String.isEmpty model.search /= String.isEmpty str

                newModel =
                    { model
                        | search = str
                        , needsRefilter = True
                        , scrollPosition =
                            if shouldResetScroll then
                                0

                            else
                                model.scrollPosition
                        , followTail =
                            if shouldResetScroll then
                                False

                            else
                                model.followTail
                    }

                -- Apply filters immediately
                filteredModel =
                    { newModel | filteredLogs = applyFilters newModel, needsRefilter = False }

                scrollCmd =
                    if shouldResetScroll then
                        Cmd.batch
                            [ Ports.scrollControl { id = model.connectionId, action = "top" }
                            , Ports.scrollControl { id = model.connectionId, action = "update" }
                            ]

                    else
                        Ports.scrollControl { id = model.connectionId, action = "update" }
            in
            ( filteredModel, scrollCmd )

        SelectLine lineNumber ->
            let
                newSelectedLine =
                    if lineNumber == -1 then
                        Nothing

                    else
                        Just lineNumber

                cmd =
                    case newSelectedLine of
                        Just line ->
                            -- Create hash link: #jobId:lineNumber
                            Ports.updateUrlHash (model.jobId ++ ":" ++ String.fromInt line)

                        Nothing ->
                            -- Clear the line part but keep job ID
                            Ports.updateUrlHash model.jobId
            in
            ( { model | selectedLine = newSelectedLine }, cmd )

        ToggleFollowTail ->
            let
                newModel =
                    { model | followTail = not model.followTail }
            in
            ( newModel
            , if not model.followTail then
                Task.perform (\_ -> ScrollToBottom) (Task.succeed ())

              else
                Cmd.none
            )

        SSEMessages value ->
            case Decode.decodeValue (Decode.list logDecoder) value of
                Ok logLines ->
                    let
                        -- Append new logs
                        newLogs =
                            List.foldl Array.push model.logs logLines

                        -- Update model with new logs
                        modelWithNewLogs =
                            { model | logs = newLogs }

                        -- Update filtered logs incrementally if filters are active
                        updatedFilteredLogs =
                            if String.isEmpty model.search && model.showDebugLogs then
                                -- No filtering needed, use all logs
                                newLogs

                            else
                                -- Append only matching new logs to existing filtered logs
                                let
                                    matchingNewLogs =
                                        logLines
                                            |> List.filter (shouldShowLog model.showDebugLogs)
                                            |> List.filter (matchesSearchTerm model.search)
                                in
                                List.foldl Array.push model.filteredLogs matchingNewLogs

                        -- Schedule scroll if following tail
                        scrollCmd =
                            if model.followTail && not (List.isEmpty logLines) then
                                Task.perform (\_ -> ScrollToBottom) (Task.succeed ())

                            else
                                Cmd.none
                    in
                    ( { modelWithNewLogs | filteredLogs = updatedFilteredLogs }
                    , scrollCmd
                    )

                Err _ ->
                    ( model, Cmd.none )

        SSEError error ->
            -- Set reconnecting state when we get an error (the JS side will handle retry)
            ( { model | error = Just error, isReconnecting = True }, Cmd.none )

        SSEConnected ->
            -- Connection established, clear error and reconnecting state
            ( { model | error = Nothing, isReconnecting = False }, Cmd.none )

        ScrollToBottom ->
            ( model, Ports.scrollControl { id = model.connectionId, action = "bottom" } )

        UserScrolled isAtBottom ->
            -- Auto-enable/disable followTail based on scroll position
            ( { model | followTail = isAtBottom }, Cmd.none )

        ScrollPositionChanged { scrollTop, scrollHeight, clientHeight } ->
            -- Update scroll position and container height
            ( { model | scrollPosition = scrollTop, containerHeight = clientHeight }, Cmd.none )

        ToggleDebugLogs ->
            -- Toggle debug log visibility and recalculate filters
            let
                newModel =
                    { model | showDebugLogs = not model.showDebugLogs, needsRefilter = True }

                -- Apply filters with new debug setting
                filteredModel =
                    { newModel
                        | filteredLogs = applyFilters newModel
                        , needsRefilter = False
                        , followTail = True -- Enable follow tail to see latest logs
                    }
            in
            ( filteredModel
            , Cmd.batch
                [ Ports.scrollControl { id = model.connectionId, action = "bottom" }
                , Ports.scrollControl { id = model.connectionId, action = "update" }
                ]
            )

        ToggleFullscreen ->
            -- Toggle fullscreen mode
            let
                cmd =
                    if model.isFullscreen then
                        Ports.exitFullscreen ()

                    else
                        Ports.requestFullscreen model.connectionId
            in
            ( model, cmd )

        FullscreenChanged isFullscreen ->
            -- Update fullscreen state when changed externally (e.g., ESC key)
            ( { model | isFullscreen = isFullscreen }, Cmd.none )


logDecoder : Decode.Decoder LogLine
logDecoder =
    Decode.map4 LogLine
        (Decode.field "timestamp" Decode.string
            |> Decode.map formatTimestamp
        )
        (Decode.field "message" Decode.string)
        (Decode.field "level" Decode.string |> Decode.maybe |> Decode.map (Maybe.withDefault "info"))
        (Decode.field "line" Decode.int)


formatTimestamp : String -> String
formatTimestamp timestamp =
    -- Format ISO timestamp (e.g., "2024-01-01T12:34:56.789Z") as HH:MM:SS.s
    case String.split "T" timestamp of
        [ _, timeWithZ ] ->
            timeWithZ
                |> String.dropRight 1
                -- Remove 'Z'
                |> (\timeStr ->
                        case String.split "." timeStr of
                            [ time, millis ] ->
                                time ++ "." ++ String.left 1 millis

                            _ ->
                                timeStr
                   )

        _ ->
            timestamp


renderAnsiText : String -> List (Html msg)
renderAnsiText str =
    let
        buffer =
            ANSI.parseEscaped (Just ANSI.defaultFormat) str
    in
    if List.isEmpty buffer.nodes then
        -- If no ANSI codes were found, just render as plain text
        [ text str ]

    else
        buffer.nodes


view : Model -> Html Msg
view model =
    case ( model.error, model.isReconnecting ) of
        ( Just error, _ ) ->
            -- Always show reconnecting state since we retry indefinitely
            div [ class "p-4 text-yellow-600 dark:text-yellow-400 bg-yellow-50 dark:bg-yellow-900/10 border border-yellow-200 dark:border-yellow-800 rounded-md" ]
                [ div [ class "flex items-center gap-2" ]
                    [ Icons.spinner [ Svg.Attributes.class "w-4 h-4 animate-spin" ]
                    , strong [] [ text "Connection lost. " ]
                    , text "Attempting to reconnect..."
                    ]
                ]

        _ ->
            -- Always show the log viewer, even while loading
            viewLogContent model


viewLogLine : Maybe Int -> Int -> LogLine -> Html Msg
viewLogLine selectedLine index log =
    let
        isSelected =
            selectedLine == Just index

        baseClasses =
            "px-2 py-1 border-b font-mono text-xs group cursor-pointer relative"
    in
    div
        [ class baseClasses
        , classList
            [ ( "bg-blue-100 dark:bg-blue-900/30 border-blue-300 dark:border-blue-700", isSelected )
            , ( "border-gray-100 dark:border-gray-800 hover:bg-gray-100 dark:hover:bg-gray-800", not isSelected )
            ]
        , onClick (SelectLine index)
        , style "height" "20px"
        ]
        [ -- Always visible content
          div [ class "flex" ]
            [ span [ class "text-gray-500 dark:text-gray-400 mr-2 select-none shrink-0" ]
                [ text log.timestamp ]
            , span [ class "text-gray-400 dark:text-gray-500 mr-1" ] [ text "|" ]
            , span [ class "text-gray-800 dark:text-gray-200 whitespace-nowrap overflow-hidden text-ellipsis flex-1 min-w-0" ]
                (renderAnsiText log.message)
            ]

        -- Hover overlay - shows full text on top
        , div [ class "hidden group-hover:block absolute left-0 top-0 w-full z-10 px-2 py-1 bg-gray-100 dark:bg-gray-800 border border-gray-300 dark:border-gray-600 shadow-lg" ]
            [ div [ class "flex" ]
                [ span [ class "text-gray-500 dark:text-gray-400 mr-2 select-none shrink-0" ]
                    [ text log.timestamp ]
                , span [ class "text-gray-400 dark:text-gray-500 mr-1" ] [ text "|" ]
                , span [ class "text-gray-800 dark:text-gray-200 whitespace-pre-wrap break-all flex-1" ]
                    (renderAnsiText log.message)
                ]
            ]
        ]



-- Constants


logLineHeight : Int
logLineHeight =
    20


scrollBuffer : Int
scrollBuffer =
    2


viewLogContent : Model -> Html Msg
viewLogContent model =
    let
        -- Use cached filtered results or all logs if no filtering needed
        filteredLogs =
            if String.isEmpty model.search && model.showDebugLogs then
                model.logs

            else
                model.filteredLogs

        totalItems =
            Array.length filteredLogs

        totalHeight =
            totalItems * logLineHeight

        -- Calculate visible range based on scroll position
        startIndex =
            floor (model.scrollPosition / toFloat logLineHeight)
                |> Basics.max 0

        visibleCount =
            ceiling (model.containerHeight / toFloat logLineHeight) + scrollBuffer

        endIndex =
            (startIndex + visibleCount)
                |> Basics.min totalItems

        visibleLogs =
            filteredLogs
                |> Array.slice startIndex endIndex
                |> Array.toIndexedList
                |> List.map (\( i, log ) -> ( i + startIndex, log ))

        renderLogLine ( index, log ) =
            div
                [ style "position" "absolute"
                , style "top" (String.fromInt (index * logLineHeight) ++ "px")
                , style "left" "0"
                , style "right" "0"
                , style "height" (String.fromInt logLineHeight ++ "px")
                ]
                [ Lazy.lazy3 viewLogLine model.selectedLine index log
                ]
    in
    div
        [ class "w-full"
        , classList [ ( "h-full flex flex-col", model.isFullscreen ) ]
        ]
        [ div
            [ class "bg-white dark:bg-gray-900 rounded-lg border border-gray-200 dark:border-gray-700 overflow-hidden"
            , classList [ ( "h-full flex flex-col", model.isFullscreen ) ]
            ]
            [ div
                [ style "overflow-y" "scroll" -- Changed from "auto" to "scroll" to always show scrollbar
                , style "position" "relative"
                , class "bg-gray-50 dark:bg-gray-950"
                , if model.isFullscreen then
                    style "height" ""

                  else
                    style "height" "600px"
                , classList [ ( "flex-1", model.isFullscreen ) ]
                , id ("log-viewer-" ++ model.connectionId)
                ]
                [ if Array.isEmpty model.logs then
                    -- Show spinner while connecting/loading or no logs
                    div [ class "p-4 text-gray-500 dark:text-gray-400 text-center" ]
                        [ if model.error == Nothing && not model.isReconnecting then
                            div [ class "flex items-center justify-center gap-2" ]
                                [ Icons.spinner [ Svg.Attributes.class "w-4 h-4 animate-spin" ]
                                , text "Connecting to log stream..."
                                ]

                          else
                            text "No logs available yet"
                        ]

                  else if Array.isEmpty filteredLogs && not (Array.isEmpty model.logs) then
                    -- Logs exist but none match the filter
                    div [ class "p-4 text-gray-500 dark:text-gray-400 text-center" ]
                        [ text "No logs match your search" ]

                  else
                    -- Virtual scrolling container with full height inner div
                    div
                        [ style "position" "relative"
                        , style "height" (String.fromInt totalHeight ++ "px")
                        ]
                        (List.map renderLogLine visibleLogs)
                ]
            , div
                [ class "border-t border-gray-200 dark:border-gray-700 px-4 py-3 flex items-center justify-between text-sm text-gray-500 dark:text-gray-400"
                , classList [ ( "shrink-0", model.isFullscreen ) ]
                ]
                [ div [ class "flex items-center gap-4" ]
                    [ text ("Total " ++ String.fromInt (Array.length filteredLogs) ++ " lines")
                    , label [ class "flex items-center gap-2 cursor-pointer" ]
                        [ input
                            [ type_ "checkbox"
                            , checked model.followTail
                            , onCheck (\_ -> ToggleFollowTail)
                            , class "rounded-sm border-gray-300 dark:border-gray-600"
                            ]
                            []
                        , text "Auto-scroll"
                        ]
                    , label [ class "flex items-center gap-2 cursor-pointer" ]
                        [ input
                            [ type_ "checkbox"
                            , checked model.showDebugLogs
                            , onCheck (\_ -> ToggleDebugLogs)
                            , class "rounded-sm border-gray-300 dark:border-gray-600"
                            ]
                            []
                        , text "Show debug logs"
                        ]
                    ]
                , div [ class "flex items-center gap-3" ]
                    [ button
                        [ onClick ToggleFullscreen
                        , class "p-2 hover:bg-gray-100 dark:hover:bg-gray-700 rounded-md transition-colors"
                        , title
                            (if model.isFullscreen then
                                "Exit fullscreen"

                             else
                                "Enter fullscreen"
                            )
                        ]
                        [ if model.isFullscreen then
                            Icons.compress [ Svg.Attributes.class "w-4 h-4" ]

                          else
                            Icons.expand [ Svg.Attributes.class "w-4 h-4" ]
                        ]
                    , div [ class "relative" ]
                        [ div [ class "absolute inset-y-0 right-0 pr-3 flex items-center pointer-events-none" ]
                            [ Icons.search [ Svg.Attributes.class "w-4 h-4" ] ]
                        , input
                            [ type_ "text"
                            , class "block w-64 pl-3 pr-10 py-2 border border-gray-300 dark:border-gray-600 rounded-md leading-5 bg-white dark:bg-gray-800 placeholder-gray-500 dark:placeholder-gray-400 focus:outline-hidden focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                            , placeholder "Search logs..."
                            , value model.search
                            , onInput SetSearch
                            ]
                            []
                        ]
                    ]
                ]
            ]
        ]


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Ports.sseMessages SSEMessages
        , Ports.sseError SSEError
        , Ports.sseConnected (always SSEConnected)
        , Ports.userScrolled UserScrolled
        , Ports.scrollPositionChanged ScrollPositionChanged
        , Ports.fullscreenChanged FullscreenChanged
        ]
