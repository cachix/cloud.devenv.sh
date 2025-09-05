module Pages.Github.Owner_.Repo_ exposing (Model, Msg, page)

import Api
import Api.Data as Api
import Api.Request.Default as Api
import Auth
import Browser.Dom as Dom
import Components.Breadcrumbs exposing (Breadcrumbs)
import Components.Button as Button
import Components.CommitJobs
import Components.Job exposing (JobViewMsg(..))
import Dict
import Effect exposing (Effect)
import Html exposing (..)
import Html.Attributes exposing (..)
import Http
import Json.Decode as Decode exposing (Decoder)
import Layouts
import Page exposing (Page)
import Process
import RemoteData exposing (WebData)
import Route exposing (Route)
import Route.Path
import Shared
import Task
import Time exposing (millisToPosix)
import Uuid exposing (Uuid)
import View exposing (View)
import WebData


toLayout : Auth.User -> Model -> Shared.Model -> { owner : String, repo : String } -> Layouts.Layout Msg
toLayout user model shared params =
    Layouts.Main
        { breadcrumbs = Components.Breadcrumbs.forRepository params
        , user = Just user
        , shared = shared
        , buttons = []
        }


page : Auth.User -> Shared.Model -> Route { owner : String, repo : String } -> Page Model Msg
page user shared route =
    Page.new
        { init = init route
        , update = update
        , subscriptions = subscriptions
        , view = view route shared
        }
        |> Page.withLayout (\model -> toLayout user model shared route.params)


type alias Model =
    { repoJobs : WebData Api.RepoJobs
    , owner : String
    , repo : String
    , commitJobsModel : Components.CommitJobs.Model
    }


init : Route { owner : String, repo : String } -> () -> ( Model, Effect Msg )
init route () =
    ( { repoJobs = RemoteData.Loading
      , owner = route.params.owner
      , repo = route.params.repo
      , commitJobsModel = Components.CommitJobs.init
      }
    , getJobsForRepo route.params.owner route.params.repo
    )


getJobsForRepo : String -> String -> Effect Msg
getJobsForRepo owner repo =
    Api.getRepoJobs owner repo
        |> Effect.sendApi (RemoteData.fromResult >> RepoJobsResponse)


type Msg
    = RepoJobsResponse (WebData Api.RepoJobs)
    | Refresh
    | CommitJobsMsg Components.CommitJobs.Msg
    | ScrollComplete -- When scrolling to an element is complete
    | ScrollFailed -- When scrolling to an element fails


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        RepoJobsResponse response ->
            let
                -- Always keep targetJobId for direct opening on initial load
                updatedModel =
                    { model | repoJobs = response }
            in
            ( updatedModel, Effect.none )

        Refresh ->
            -- Don't clear existing view states or target job ID when refreshing
            -- This keeps the UI state stable between refreshes
            ( model, getJobsForRepo model.owner model.repo )

        ScrollComplete ->
            -- We've successfully scrolled to the element
            ( model, Effect.none )

        ScrollFailed ->
            -- Scrolling failed, but we can continue
            ( model, Effect.none )

        CommitJobsMsg subMsg ->
            let
                ( updatedJobsModel, jobsEffect ) =
                    Components.CommitJobs.update model.owner model.repo "" subMsg model.commitJobsModel

                mappedEffect =
                    Effect.map CommitJobsMsg jobsEffect

                -- Analyze the message for special handling of URL and state updates
                extraEffect =
                    case subMsg of
                        Components.CommitJobs.RetryJobResponse uuid response ->
                            case response of
                                RemoteData.Success jobResponse ->
                                    let
                                        newJobId =
                                            Uuid.toString jobResponse.job.id

                                        commitSha =
                                            jobResponse.commit.rev
                                    in
                                    Effect.batch
                                        [ getJobsForRepo model.owner model.repo
                                        , Effect.pushRoute
                                            { path =
                                                Route.Path.Github_Owner__Repo__Rev_
                                                    { owner = model.owner
                                                    , repo = model.repo
                                                    , rev = commitSha
                                                    }
                                            , query = Dict.empty
                                            , hash = Just newJobId
                                            }
                                        ]

                                _ ->
                                    Effect.none

                        _ ->
                            Effect.none

                -- Create refresh effect for operations that need it
                refreshEffect =
                    case subMsg of
                        Components.CommitJobs.JobViewMsg _ (CancelJobRequest _) ->
                            getJobsForRepo model.owner model.repo

                        _ ->
                            Effect.none
            in
            ( { model | commitJobsModel = updatedJobsModel }
            , Effect.batch
                [ if extraEffect == Effect.none then
                    mappedEffect

                  else
                    extraEffect
                , refreshEffect
                ]
            )



-- Helper function to scroll to an element by ID with an offset


scrollToElementEffect : String -> Effect Msg
scrollToElementEffect elementId =
    Effect.sendCmd
        (Process.sleep 100
            |> Task.andThen
                (\_ ->
                    Dom.getElement elementId
                        |> Task.andThen
                            (\elementInfo ->
                                -- Scroll element into view with some offset from top
                                Dom.setViewport 0 (elementInfo.element.y - 100)
                            )
                )
            |> Task.attempt
                (\result ->
                    case result of
                        Ok _ ->
                            ScrollComplete

                        Err _ ->
                            ScrollFailed
                )
        )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 5000 (\_ -> Refresh)
        , Sub.map CommitJobsMsg (Components.CommitJobs.subscriptions model.commitJobsModel)
        ]


view : Route { owner : String, repo : String } -> Shared.Model -> Model -> View Msg
view route shared model =
    let
        params =
            route.params

        selectedJobId =
            route.hash
                |> Maybe.withDefault ""
    in
    { title = params.owner ++ "/" ++ params.repo ++ " - Jobs"
    , body =
        [ div [ class "container mx-auto py-6" ]
            [ WebData.toHtml
                (viewRepoJobs params shared model selectedJobId)
                model.repoJobs
            ]
        ]
    }


viewRepoJobs : { owner : String, repo : String } -> Shared.Model -> Model -> String -> Api.RepoJobs -> Html Msg
viewRepoJobs params shared model selectedJobId repoJobs =
    case repoJobs.commits of
        [] ->
            div [ class "text-center py-12 bg-light/30 dark:bg-dark-surface rounded-lg border border-light dark:border-dark-border" ]
                [ p [ class "text-secondary dark:text-dark-text" ]
                    [ text "No jobs found for this repository" ]
                ]

        _ ->
            div [ class "space-y-4" ]
                (List.map
                    (\commit ->
                        -- For each commit, use the CommitJobs component
                        Html.map CommitJobsMsg
                            (Components.CommitJobs.commitJobsView
                                { owner = params.owner, repo = params.repo, rev = commit.rev }
                                shared
                                model.commitJobsModel
                                selectedJobId
                                commit
                            )
                    )
                    repoJobs.commits
                )
