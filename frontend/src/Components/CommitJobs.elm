module Components.CommitJobs exposing (Model, Msg(..), commitJobsView, init, subscriptions, update)

import Api
import Api.Data as Api
import Api.Request.Default as Api
import Browser.Dom as Dom
import Components.GitHubCommit exposing (viewCommitInfo)
import Components.Job exposing (JobViewMsg(..), viewJob)
import Components.ListTile as ListTile
import Components.LogViewer as LogViewer
import Dict exposing (Dict)
import Effect exposing (Effect)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Lazy
import Ports
import RemoteData exposing (WebData)
import Route
import Route.Path
import Shared
import Task
import Time
import Uuid
import WebData


{-| Shared model for commit jobs view
-}
type alias Model =
    { jobViewStates : Dict String { isDropdownOpen : Bool, isLoading : Bool }
    , retryErrors : Dict String String -- Store retry errors by job ID
    , logViewers : Dict String LogViewer.Model -- Store LogViewer instances by job ID
    }


{-| Shared msg type for commit jobs view
-}
type Msg
    = JobViewMsg String JobViewMsg
    | ToggleJobDropdown String Bool
    | RetryJobResponse Uuid.Uuid (WebData Api.JobResponse)
    | ClearJobLoading String
    | LogViewerMsg String LogViewer.Msg
    | ToggleLogViewerWithData String Api.JobResponse


{-| Initialize the model
-}
init : Model
init =
    { jobViewStates = Dict.empty
    , retryErrors = Dict.empty
    , logViewers = Dict.empty
    }


{-| Default job view state
-}
defaultJobViewState : { isDropdownOpen : Bool, isLoading : Bool }
defaultJobViewState =
    { isDropdownOpen = False, isLoading = False }


{-| Get current job view state with default fallback
-}
getJobViewState : String -> Model -> { isDropdownOpen : Bool, isLoading : Bool }
getJobViewState jobId model =
    Dict.get jobId model.jobViewStates
        |> Maybe.withDefault defaultJobViewState


{-| Update job view state with a transformation function
-}
updateJobViewState : String -> ({ isDropdownOpen : Bool, isLoading : Bool } -> { isDropdownOpen : Bool, isLoading : Bool }) -> Model -> Model
updateJobViewState jobId updater model =
    let
        currentState =
            getJobViewState jobId model

        updatedState =
            updater currentState
    in
    { model | jobViewStates = Dict.insert jobId updatedState model.jobViewStates }


{-| Helper function to prepare a job for an API action by setting loading state
-}
setJobLoading : String -> Model -> ( Model, { isDropdownOpen : Bool, isLoading : Bool } )
setJobLoading jobId model =
    let
        updatedModel =
            updateJobViewState jobId
                (\state -> { state | isLoading = True, isDropdownOpen = False })
                model
    in
    ( updatedModel, getJobViewState jobId updatedModel )


{-| Update function for handling job-related messages
-}
update : String -> String -> String -> Msg -> Model -> ( Model, Effect Msg )
update owner repo rev msg model =
    case msg of
        RetryJobResponse uuid response ->
            let
                jobIdStr =
                    Uuid.toString uuid

                -- Turn off loading state regardless of the result
                updatedModel =
                    updateJobViewState jobIdStr (\state -> { state | isLoading = False }) model
            in
            case response of
                RemoteData.Success jobResponse ->
                    -- Clear any previous error and redirect to the new job
                    let
                        newJobId =
                            Uuid.toString jobResponse.job.id

                        path =
                            Route.Path.Github_Owner__Repo__Rev_ { owner = owner, repo = repo, rev = rev }

                        clearedErrorModel =
                            { updatedModel | retryErrors = Dict.remove jobIdStr model.retryErrors }
                    in
                    ( clearedErrorModel
                    , Effect.batch
                        [ Effect.pushRoute { path = path, query = Dict.empty, hash = Just newJobId }
                        ]
                    )

                RemoteData.Failure error ->
                    -- Store the error message in the model
                    let
                        errorMessage =
                            WebData.errorToString error

                        errorModel =
                            { updatedModel | retryErrors = Dict.insert jobIdStr errorMessage model.retryErrors }
                    in
                    ( errorModel
                    , Effect.none
                    )

                _ ->
                    -- If loading, just refresh the current view
                    ( updatedModel, Effect.none )

        ClearJobLoading jobId ->
            -- Helper to clear loading state for any job action
            ( updateJobViewState jobId (\state -> { state | isLoading = False }) model
            , Effect.none
            )

        ToggleJobDropdown jobId isOpen ->
            ( updateJobViewState jobId (\state -> { state | isDropdownOpen = isOpen }) model
            , Effect.none
            )

        JobViewMsg jobId jobViewMsg ->
            case jobViewMsg of
                ToggleLogViewer ->
                    -- This should be handled by the parent through ToggleLogViewerWithData
                    ( model, Effect.none )

                CancelJobRequest uuid ->
                    let
                        ( updatedModel, _ ) =
                            setJobLoading (Uuid.toString uuid) model
                    in
                    ( updatedModel
                    , Api.cancelJob uuid
                        |> Effect.sendApi (\_ -> ClearJobLoading (Uuid.toString uuid))
                    )

                RetryJobRequest uuid ->
                    let
                        ( updatedModel, _ ) =
                            setJobLoading (Uuid.toString uuid) model
                    in
                    ( updatedModel
                    , Api.retryJob uuid
                        |> Effect.sendApi (RemoteData.fromResult >> RetryJobResponse uuid)
                    )

                ToggleDropdown isOpen ->
                    update owner repo rev (ToggleJobDropdown jobId isOpen) model

        LogViewerMsg jobId logViewerMsg ->
            case Dict.get jobId model.logViewers of
                Just logViewer ->
                    let
                        ( updatedLogViewer, logViewerCmd ) =
                            LogViewer.update logViewerMsg logViewer

                        updatedModel =
                            { model | logViewers = Dict.insert jobId updatedLogViewer model.logViewers }
                    in
                    ( updatedModel
                    , Effect.sendCmd (Cmd.map (LogViewerMsg jobId) logViewerCmd)
                    )

                Nothing ->
                    ( model, Effect.none )

        ToggleLogViewerWithData jobId jobResponse ->
            let
                -- Check if LogViewer currently exists for this job
                isCurrentlyOpen =
                    Dict.member jobId model.logViewers

                -- Handle LogViewer initialization/cleanup
                ( updatedLogViewers, logViewerEffect ) =
                    if not isCurrentlyOpen then
                        -- Initialize LogViewer if not already open
                        let
                            connectionId =
                                "log-viewer-" ++ jobId

                            ( logViewer, logViewerCmd ) =
                                LogViewer.init connectionId jobResponse.logUrl jobId
                        in
                        ( Dict.insert jobId logViewer model.logViewers
                        , Effect.sendCmd (Cmd.map (LogViewerMsg jobId) logViewerCmd)
                        )

                    else
                        -- Remove LogViewer if currently open
                        case Dict.get jobId model.logViewers of
                            Just logViewer ->
                                ( Dict.remove jobId model.logViewers
                                , Effect.sendCmd (Ports.disconnectSSE logViewer.connectionId)
                                )

                            Nothing ->
                                -- This shouldn't happen but handle gracefully
                                ( model.logViewers
                                , Effect.none
                                )
            in
            ( { model | logViewers = updatedLogViewers }
                |> updateJobViewState jobId (\state -> { state | isLoading = False })
            , logViewerEffect
            )


{-| View function for rendering a list of commits and their jobs
-}
commitJobsView : { owner : String, repo : String, rev : String } -> Shared.Model -> Model -> String -> Api.Commit -> Html Msg
commitJobsView params shared model selectedJobId commit =
    let
        commitInfoHeader =
            viewCommitInfo
                { rev = commit.rev
                , ref = commit.ref
                , message = commit.message
                , author = commit.author
                , owner = params.owner
                , repo = params.repo
                }

        -- Filter out jobs that have been retried (only show the latest ones)
        activeJobs =
            List.filter (\jobResponse -> jobResponse.job.retriedJobId == Nothing) commit.jobs

        -- Create job rows from active jobs only
        jobRows =
            List.map (viewCommitJob params shared model selectedJobId) activeJobs
    in
    ListTile.new
        |> ListTile.withHeader commitInfoHeader
        |> ListTile.withRows jobRows
        |> ListTile.view


{-| View function for rendering a single job in a commit
-}
viewCommitJob : { owner : String, repo : String, rev : String } -> Shared.Model -> Model -> String -> Api.JobResponse -> Html Msg
viewCommitJob params shared model selectedJobId jobResponse =
    let
        jobId =
            Uuid.toString jobResponse.job.id

        -- Get or create the job view model for dropdown state
        jobViewModel =
            getJobViewState jobId model

        -- Check if LogViewer is open for this job
        isLogViewerOpen =
            Dict.member jobId model.logViewers

        -- Check if we need to open LogViewer based on URL hash
        shouldOpenFromHash =
            jobId == selectedJobId && not isLogViewerOpen

        handleJobViewMsg =
            \msg ->
                case msg of
                    ToggleLogViewer ->
                        ToggleLogViewerWithData jobId jobResponse

                    _ ->
                        JobViewMsg jobId msg

        -- Get any retry error for this job
        retryError =
            Dict.get jobId model.retryErrors

        -- Get the LogViewer HTML if it exists
        maybeLogViewer =
            Dict.get jobId model.logViewers
                |> Maybe.map (\logViewer -> Html.map (LogViewerMsg jobId) (Html.Lazy.lazy LogViewer.view logViewer))
    in
    div
        [ class "px-5 py-3 block" ]
        [ Components.Job.viewJob params.owner params.repo shared.now () handleJobViewMsg jobViewModel retryError jobResponse maybeLogViewer ]


{-| Subscriptions for LogViewer instances
-}
subscriptions : Model -> Sub Msg
subscriptions model =
    let
        logViewerSubs =
            model.logViewers
                |> Dict.toList
                |> List.map
                    (\( jobId, logViewer ) ->
                        Sub.map (LogViewerMsg jobId) (LogViewer.subscriptions logViewer)
                    )
    in
    Sub.batch logViewerSubs
