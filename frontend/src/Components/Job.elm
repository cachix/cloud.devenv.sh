module Components.Job exposing (JobViewMsg(..), formatJobDuration, getJobStartedAtText, getPlatformText, getStatusInfo, viewJob, viewJobDetails, viewJobStatus, viewJobStatusWithLink, viewSimpleJob)

import Api.Data as Api
import Components.Button as Button
import Components.Dropdown as Dropdown
import Components.LogViewer as LogViewer
import DateFormat.Relative exposing (relativeTime)
import Duration.Format exposing (formatHMS)
import Html exposing (..)
import Html.Attributes exposing (attribute, class, href, id, title)
import Html.Events exposing (onClick)
import Icons
import Json.Decode as Decode
import RemoteData exposing (WebData)
import Route
import Route.Path
import Svg.Attributes
import Time
import Uuid


{-| Helper to display an icon with text in a consistent format
-}
viewIconWithText : Html msg -> String -> String -> Html msg
viewIconWithText icon label value =
    if String.isEmpty value then
        text ""

    else
        div [ class "flex items-center gap-1" ]
            [ icon
            , span [ class "text-xs" ] [ text value ]
            ]


{-| A simplified, non-interactive job view for the owner repos listing.
This is used instead of viewJob because we don't need the full
interactive features (log viewer, cancel/retry buttons) in this context.
-}
viewSimpleJob : Time.Posix -> Api.JobResponse -> Html msg
viewSimpleJob now jobResponse =
    let
        job =
            jobResponse.job

        durationText =
            formatJobDuration job.startedAt job.finishedAt now

        startedAtText =
            getJobStartedAtText now job.startedAt
    in
    div [ class "flex items-center" ]
        [ -- Status - fixed width
          div [ class "w-8" ]
            [ viewJobStatus job.status ]

        -- Platform - fixed width
        , div [ class "w-32" ]
            [ viewIconWithText (Icons.computer []) "Platform" (getPlatformText job.platform) ]

        -- Start time - fixed width
        , div [ class "w-32 tabular-nums" ]
            [ viewIconWithText (Icons.calendar []) "Started" startedAtText ]

        -- Duration - fixed width
        , div [ class "w-24 tabular-nums" ]
            [ viewIconWithText (Icons.clock []) "Duration" durationText ]

        -- Job details (CPU/Memory) - aligned to the right
        , div [ class "ml-auto" ]
            [ viewJobDetails job ]
        ]


{-| Creates a status badge for a job
-}
viewJobStatus : Api.JobStatus -> Html msg
viewJobStatus status =
    let
        ( statusText, bgColor, icon ) =
            getStatusInfo status
    in
    div
        [ class ("inline-flex items-center justify-center p-1 rounded-full " ++ bgColor)
        , title statusText
        ]
        [ icon ]


{-| Creates a linked job status that links to the job details page
-}
viewJobStatusWithLink : Api.JobStatus -> String -> Html msg
viewJobStatusWithLink status jobId =
    let
        ( statusText, bgColor, icon ) =
            getStatusInfo status
    in
    a
        [ href ("/jobs/" ++ jobId)
        , class "inline-block hover:opacity-80 transition-opacity"
        ]
        [ div
            [ class ("inline-flex items-center justify-center p-1 rounded-full " ++ bgColor)
            , title statusText
            ]
            [ icon ]
        ]


{-| Returns (text, background color, icon) for a job status
-}
getStatusInfo : Api.JobStatus -> ( String, String, Html msg )
getStatusInfo status =
    case status of
        Api.JobStatusJobStatusOneOf1 Api.JobStatusOneOf1Running ->
            ( "Running", "bg-gray-200 dark:bg-dark-surface", Icons.running [] )

        Api.JobStatusJobStatusOneOf Api.JobStatusOneOfQueued ->
            ( "Queued", "bg-gray-200 dark:bg-dark-surface", Icons.queued [] )

        Api.JobStatusJobStatusOneOf2 statusOneOf ->
            case statusOneOf.complete of
                Api.CompletionStatusSuccess ->
                    ( "Success", "bg-green-100 dark:bg-green-900/30", Icons.success [] )

                Api.CompletionStatusFailed ->
                    ( "Failed", "bg-red-100 dark:bg-red-900/30", Icons.failed [] )

                Api.CompletionStatusCancelled ->
                    ( "Cancelled", "bg-yellow-100 dark:bg-yellow-900/30", Icons.cancelled [] )

                Api.CompletionStatusTimedOut ->
                    ( "Timed Out", "bg-yellow-100 dark:bg-yellow-900/30", Icons.timedOut [] )

                Api.CompletionStatusSkipped ->
                    ( "Skipped", "bg-gray-200 dark:bg-dark-surface", Icons.skipped [] )


{-| Returns a readable string for a platform
-}
getPlatformText : Api.Platform -> String
getPlatformText platform =
    case platform of
        Api.PlatformX8664Linux ->
            "x86_64-linux"

        Api.PlatformAArch64Darwin ->
            "aarch64-darwin"


{-| Renders the job configuration (CPU and memory) as a concise set of labeled stats
-}
viewJobDetails : Api.Job -> Html msg
viewJobDetails job =
    div [ class "flex items-center gap-4" ]
        [ div [ class "flex items-center gap-1" ]
            [ Icons.cpu [ Svg.Attributes.class "w-4 h-4" ]
            , span [ class "text-xs" ] [ text (String.fromInt job.cpus ++ " CPU") ]
            ]
        , div [ class "flex items-center gap-1" ]
            [ Icons.memory [ Svg.Attributes.class "w-4 h-4" ]
            , span [ class "text-xs" ] [ text (String.fromInt job.memoryMb ++ " MB") ]
            ]
        ]


{-| Formats the duration between start and end times
-}
formatJobDuration : Maybe Time.Posix -> Maybe Time.Posix -> Time.Posix -> String
formatJobDuration maybeStartedAt maybeFinishedAt now =
    case ( maybeStartedAt, maybeFinishedAt ) of
        ( Just startTime, Just endTime ) ->
            -- For completed jobs, format duration using formatHMS
            formatHMS startTime endTime

        ( Just startTime, Nothing ) ->
            -- For running jobs, calculate duration with current time
            formatHMS startTime now

        _ ->
            ""


{-| Gets a human-readable started at text for a job
-}
getJobStartedAtText : Time.Posix -> Maybe Time.Posix -> String
getJobStartedAtText now maybeStartedAt =
    case maybeStartedAt of
        Just time ->
            relativeTime now time

        Nothing ->
            "Not started yet"


{-| Renders a detailed view of a job with optional cancel button
-}
type JobViewMsg
    = ToggleLogViewer
    | CancelJobRequest Uuid.Uuid
    | RetryJobRequest Uuid.Uuid
    | ToggleDropdown Bool


viewJob : String -> String -> Time.Posix -> job -> (JobViewMsg -> msg) -> { isDropdownOpen : Bool, isLoading : Bool } -> Maybe String -> Api.JobResponse -> Maybe (Html msg) -> Html msg
viewJob owner repo now cancelResponse msgWrapper model errorMessage jobResponse maybeLogViewer =
    let
        job =
            jobResponse.job

        github =
            jobResponse.github

        statusDisplay =
            viewJobStatus job.status

        statusText =
            case job.status of
                Api.JobStatusJobStatusOneOf2 status ->
                    case status.complete of
                        Api.CompletionStatusSuccess ->
                            "Success"

                        Api.CompletionStatusFailed ->
                            "Failed"

                        Api.CompletionStatusCancelled ->
                            "Cancelled"

                        Api.CompletionStatusTimedOut ->
                            "Timed Out"

                        Api.CompletionStatusSkipped ->
                            "Skipped"

                Api.JobStatusJobStatusOneOf Api.JobStatusOneOfQueued ->
                    "Queued"

                Api.JobStatusJobStatusOneOf1 Api.JobStatusOneOf1Running ->
                    "Running"

        isQueued =
            statusText == "Queued"

        platformText =
            getPlatformText job.platform

        startedAtText =
            getJobStartedAtText now job.startedAt

        durationText =
            formatJobDuration job.startedAt job.finishedAt now

        -- Show cancel button for running and queued jobs
        showCancelButton =
            case job.status of
                Api.JobStatusJobStatusOneOf1 Api.JobStatusOneOf1Running ->
                    True

                Api.JobStatusJobStatusOneOf Api.JobStatusOneOfQueued ->
                    True

                _ ->
                    False

        -- Show retry button for completed jobs with non-success status
        showRetryButton =
            case job.status of
                Api.JobStatusJobStatusOneOf2 statusOneOf ->
                    case statusOneOf.complete of
                        Api.CompletionStatusSuccess ->
                            False

                        -- Show retry for all other completion statuses (Failed, Cancelled, TimedOut, Skipped)
                        _ ->
                            True

                -- Always allow retrying jobs, even if they've been retried before
                _ ->
                    False

        -- Show retry relationships in both directions
        -- If this job has a previous job ID, it's a retry of that job
        -- If this job has a retried job ID, it has been retried by another job
        -- Show if this job is a retry of another job
        retryOfIndicator =
            case job.previousJobId of
                Just prevJobId ->
                    -- This job is a retry of a previous job
                    div
                        [ class "inline-flex items-center gap-1 ml-1 px-1.5 py-0.5 rounded-full bg-amber-100 dark:bg-amber-900 text-xs text-amber-800 dark:text-amber-200"
                        , title "This job is a retry of a previous job"
                        ]
                        [ Icons.arrowPath [ Svg.Attributes.class "w-3 h-3 rotate-180" ]
                        , text "Retry of "
                        , a
                            [ class "underline hover:text-amber-600 dark:hover:text-amber-300"
                            , href ("#" ++ Uuid.toString prevJobId)
                            , title "View the original job that was retried"
                            ]
                            [ text "previous job" ]
                        ]

                Nothing ->
                    text ""

        -- Show if this job has been retried by another job
        retriedByIndicator =
            case job.retriedJobId of
                Just retriedJobId ->
                    -- This job has been retried by a newer job
                    div
                        [ class "inline-flex items-center gap-1 ml-1 px-1.5 py-0.5 rounded-full bg-indigo-100 dark:bg-indigo-900 text-xs text-indigo-800 dark:text-indigo-200"
                        , title "This job has been retried by a newer job"
                        ]
                        [ Icons.arrowPath [ Svg.Attributes.class "w-3 h-3" ]
                        , text "Retried by "
                        , a
                            [ class "underline hover:text-indigo-600 dark:hover:text-indigo-300"
                            , href ("#" ++ Uuid.toString retriedJobId)
                            , title "View the new job that retried this one"
                            ]
                            [ text "newer job" ]
                        ]

                Nothing ->
                    text ""

        -- Create dropdown items list
        dropdownItems =
            List.filterMap identity
                [ -- Retry button (only shown for failed jobs)
                  if showRetryButton then
                    Just
                        (Dropdown.viewItem
                            { onClick =
                                if model.isLoading then
                                    msgWrapper (ToggleDropdown False)
                                    -- No action when loading

                                else
                                    msgWrapper (RetryJobRequest job.id)
                            , icon = Just (Icons.arrowPath [ Svg.Attributes.class "w-4 h-4" ])
                            , label = "Retry"
                            , isDanger = False
                            , tooltip = Just "Create a new job with the same configuration"
                            }
                        )

                  else
                    Nothing

                -- Cancel button (only shown for running jobs)
                , if showCancelButton then
                    Just
                        (Dropdown.viewItem
                            { onClick =
                                if model.isLoading then
                                    msgWrapper (ToggleDropdown False)
                                    -- No action when loading

                                else
                                    msgWrapper (CancelJobRequest job.id)
                            , icon = Just (Icons.xMark [ Svg.Attributes.class "w-4 h-4" ])
                            , label = "Cancel"
                            , isDanger = True
                            , tooltip = Just "Stop the currently running job"
                            }
                        )

                  else
                    Nothing
                ]

        -- Only show dropdown if there are actions available
        hasActions =
            not (List.isEmpty dropdownItems)

        -- Only allow opening logs if job has started
        canOpenLogs =
            job.startedAt /= Nothing
    in
    div [ class "flex flex-col gap-2" ]
        [ div
            [ class "flex items-center justify-between"
            , id (Uuid.toString job.id)
            ]
            [ -- Left side (clickable area for log viewer)
              div
                (if canOpenLogs then
                    [ class "flex-1 flex items-center gap-4 hover:bg-light/50 dark:hover:bg-dark-surface/50 hover:text-primary dark:hover:text-primary transition-colors cursor-pointer rounded-lg -m-2 p-2"
                    , onClick (msgWrapper ToggleLogViewer)
                    ]

                 else
                    [ class "flex-1 flex items-center gap-4" ]
                )
                [ -- Status and platform info
                  statusDisplay
                , div [ class "flex items-center gap-1" ]
                    [ Icons.computer []
                    , span [ class "text-xs" ] [ text (getPlatformText job.platform) ]
                    ]
                , case job.startedAt of
                    Just _ ->
                        div [ class "flex items-center gap-1 tabular-nums ml-4", title "Started" ]
                            [ Icons.calendar []
                            , span [ class "text-xs" ] [ text startedAtText ]
                            ]

                    Nothing ->
                        text ""
                , if String.isEmpty durationText then
                    text ""

                  else
                    div [ class "flex items-center gap-1 tabular-nums ml-4", title "Duration" ]
                        [ Icons.clock []
                        , span [ class "text-xs" ] [ text durationText ]
                        ]
                , retryOfIndicator
                , retriedByIndicator

                -- Job details
                , div [ class "ml-auto flex items-center" ]
                    [ viewJobDetails job
                    ]
                ]

            -- Right side: Actions dropdown (completely separate)
            , if hasActions then
                div [ class "flex-none pl-2 mr-2" ]
                    [ if model.isLoading then
                        -- Show a spinner button when loading that's not clickable
                        div [ class Dropdown.iconButtonStyle ]
                            [ Icons.spinner
                                [ Svg.Attributes.class "w-4! h-4! text-gray-400 dark:text-gray-500" ]
                            ]

                      else
                        -- Show the dropdown when not loading
                        Dropdown.dropdown
                            { identifier = "job-actions-" ++ Uuid.toString job.id
                            , toggleButton = Icons.dotsVertical [ Svg.Attributes.class "w-4 h-4" ]
                            , toggleButtonClass = Dropdown.iconButtonStyle
                            , items = dropdownItems
                            , onToggle = \isOpen -> msgWrapper (ToggleDropdown isOpen)
                            , isOpen = model.isDropdownOpen
                            }
                    ]

              else
                -- Add invisible placeholder to maintain alignment when no actions
                div [ class "flex-none w-8 mr-2" ] [ text "" ]
            ]

        -- Error message section
        , case errorMessage of
            Just error ->
                div [ class "mx-5 mt-2 px-4 py-2 bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-300 rounded-md text-sm" ]
                    [ div [ class "flex items-center gap-2" ]
                        [ Icons.exclamation [ Svg.Attributes.class "w-4 h-4" ]
                        , text error
                        ]
                    ]

            Nothing ->
                text ""

        -- Log viewer section
        , case maybeLogViewer of
            Just logViewer ->
                div [ class "mt-3" ]
                    [ logViewer ]

            Nothing ->
                text ""
        ]
