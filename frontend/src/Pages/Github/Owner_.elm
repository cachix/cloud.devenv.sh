module Pages.Github.Owner_ exposing (Model, Msg, page)

import Api
import Api.Data as Api
import Api.Request.Default as Api
import Auth
import Components.Breadcrumbs exposing (Breadcrumbs)
import Components.Button as Button
import Components.OwnerRepos exposing (viewEmptyDashboard, viewOwner)
import Effect exposing (Effect)
import Html exposing (..)
import Html.Attributes exposing (..)
import Icons
import Layouts
import Page exposing (Page)
import RemoteData exposing (WebData)
import Route exposing (Route)
import Route.Path
import Shared
import Shared.Model
import Time
import View exposing (View)
import WebData


toLayout : Auth.User -> Model -> Shared.Model -> { owner : String } -> Layouts.Layout Msg
toLayout user model shared params =
    Layouts.Main
        { breadcrumbs = Components.Breadcrumbs.forOwner { owner = params.owner }
        , user = Just user
        , shared = shared
        , buttons =
            [ case shared.config of
                RemoteData.Success config ->
                    Button.new
                        { label = "Add a GitHub repo"
                        , action = Button.Href ("https://github.com/apps/" ++ config.githubAppName ++ "/installations/new")
                        , icon = Just Icons.github
                        }
                        |> Button.view

                _ ->
                    -- Show loading state for the button until config is loaded
                    Button.new
                        { label = "Loading..."
                        , action = Button.Href ""
                        , icon = Just Icons.github
                        }
                        |> Button.withDisabled True
                        |> Button.view
            ]
        }


page : Auth.User -> Shared.Model -> Route { owner : String } -> Page Model Msg
page user shared route =
    Page.new
        { init = init user shared route.params
        , update = update route
        , subscriptions = subscriptions shared
        , view = view shared route.params
        }
        |> Page.withLayout (\model -> toLayout user model shared route.params)


type alias Model =
    { ownersWithReposResponse : WebData (List Api.OwnerWithRepos)
    , owner : String
    }


init : Auth.User -> Shared.Model -> { owner : String } -> () -> ( Model, Effect Msg )
init user shared_ params () =
    ( { ownersWithReposResponse = RemoteData.Loading
      , owner = params.owner
      }
    , getOwnersWithRepos
    )


getOwnersWithRepos : Effect Msg
getOwnersWithRepos =
    Api.getRepos
        |> Effect.sendApi (RemoteData.fromResult >> OwnersWithReposResponse)


type Msg
    = OwnersWithReposResponse (WebData (List Api.OwnerWithRepos))
    | Refresh Time.Posix


update : Route { owner : String } -> Msg -> Model -> ( Model, Effect Msg )
update route msg model =
    case msg of
        OwnersWithReposResponse response ->
            let
                shouldRedirectToNotFound =
                    case response of
                        RemoteData.Success owners ->
                            List.filter (\owner -> owner.login == route.params.owner) owners
                                |> List.isEmpty

                        _ ->
                            False
            in
            if shouldRedirectToNotFound then
                ( model
                , Effect.replaceRoutePath Route.Path.NotFound_
                )

            else
                ( { model | ownersWithReposResponse = response }
                , Effect.none
                )

        Refresh _ ->
            ( model
            , getOwnersWithRepos
            )


subscriptions : Shared.Model -> Model -> Sub Msg
subscriptions shared model =
    case shared.user of
        RemoteData.Success _ ->
            Time.every 10000 Refresh

        -- Refresh every 10 seconds to reduce API load
        _ ->
            Sub.none


view : Shared.Model -> { owner : String } -> Model -> View Msg
view shared params model =
    { title = params.owner ++ "'s Repositories"
    , body =
        [ div [ class "container mx-auto py-6" ]
            [ WebData.toHtml
                (viewFilteredOwners shared params.owner)
                model.ownersWithReposResponse
            ]
        ]
    }


viewFilteredOwners : Shared.Model -> String -> List Api.OwnerWithRepos -> Html Msg
viewFilteredOwners shared currentOwner owners =
    let
        filteredOwners =
            List.filter (\owner -> owner.login == currentOwner) owners
    in
    case filteredOwners of
        [] ->
            viewEmptyDashboard shared

        _ ->
            div [ class "mt-4 space-y-8" ]
                (List.map (viewOwner shared) filteredOwners)
