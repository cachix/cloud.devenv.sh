module Pages.Github.Owner_.Repo_.Rev_ exposing (Model, Msg, page)

import Api
import Api.Data as Api
import Api.Request.Default as Api
import Auth
import Browser.Dom as Dom
import Components.Breadcrumbs exposing (Breadcrumbs)
import Components.CommitJobs
import Components.Job exposing (JobViewMsg(..))
import Effect exposing (Effect)
import Html exposing (..)
import Html.Attributes exposing (..)
import Layouts
import Page exposing (Page)
import RemoteData exposing (WebData)
import Route exposing (Route)
import Route.Path
import Shared
import Time exposing (millisToPosix)
import Uuid
import View exposing (View)
import WebData


toLayout : Auth.User -> Model -> Shared.Model -> { owner : String, repo : String, rev : String } -> Layouts.Layout Msg
toLayout user model shared params =
    Layouts.Main
        { breadcrumbs = Components.Breadcrumbs.forCommit params
        , user = Just user
        , shared = shared
        , buttons = []
        }


page : Auth.User -> Shared.Model -> Route { owner : String, repo : String, rev : String } -> Page Model Msg
page user shared route =
    Page.new
        { init = init route
        , update = update route
        , subscriptions = subscriptions
        , view = view route shared
        }
        |> Page.withLayout (\model -> toLayout user model shared route.params)


type alias Model =
    { commit : WebData Api.Commit
    , owner : String
    , repo : String
    , rev : String
    , commitJobsModel : Components.CommitJobs.Model
    }


init : Route { owner : String, repo : String, rev : String } -> () -> ( Model, Effect Msg )
init route () =
    ( { commit = RemoteData.Loading
      , owner = route.params.owner
      , repo = route.params.repo
      , rev = route.params.rev
      , commitJobsModel = Components.CommitJobs.init
      }
    , getCommit route.params.owner route.params.repo route.params.rev
    )


getCommit : String -> String -> String -> Effect Msg
getCommit owner repo rev =
    Api.getRev owner repo rev
        |> Effect.sendApi (RemoteData.fromResult >> CommitResponse)


type Msg
    = CommitResponse (WebData Api.Commit)
    | Refresh
    | CommitJobsMsg Components.CommitJobs.Msg


update : Route { owner : String, repo : String, rev : String } -> Msg -> Model -> ( Model, Effect Msg )
update route msg model =
    case msg of
        CommitResponse response ->
            case response of
                RemoteData.Success commit ->
                    ( { model | commit = response }
                    , Effect.none
                    )

                _ ->
                    ( { model | commit = response }
                    , Effect.none
                    )

        Refresh ->
            ( model
            , getCommit model.owner model.repo model.rev
            )

        CommitJobsMsg subMsg ->
            let
                ( updatedJobsModel, jobsEffect ) =
                    Components.CommitJobs.update model.owner model.repo model.rev subMsg model.commitJobsModel

                mappedEffect =
                    Effect.map CommitJobsMsg jobsEffect

                -- Only refresh on specific actions that change job state
                refreshEffect =
                    case subMsg of
                        Components.CommitJobs.JobViewMsg _ (CancelJobRequest _) ->
                            getCommit model.owner model.repo model.rev

                        Components.CommitJobs.RetryJobResponse _ _ ->
                            getCommit model.owner model.repo model.rev

                        _ ->
                            Effect.none
            in
            ( { model | commitJobsModel = updatedJobsModel }
            , Effect.batch
                [ mappedEffect
                , refreshEffect
                ]
            )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.batch
        [ Time.every 5000 (\_ -> Refresh)
        , Sub.map CommitJobsMsg (Components.CommitJobs.subscriptions model.commitJobsModel)
        ]


view : Route { owner : String, repo : String, rev : String } -> Shared.Model -> Model -> View Msg
view route shared model =
    let
        params =
            route.params

        selectedJobId =
            route.hash
                |> Maybe.withDefault ""
    in
    { title = params.owner ++ "/" ++ params.repo ++ " @ " ++ String.left 7 params.rev
    , body =
        [ div [ class "container mx-auto py-6" ]
            [ WebData.toHtml
                (\commit ->
                    Html.map CommitJobsMsg
                        (Components.CommitJobs.commitJobsView params shared model.commitJobsModel selectedJobId commit)
                )
                model.commit
            ]
        ]
    }
