module Components.OwnerRepos exposing
    ( viewEmptyDashboard
    , viewOwner
    , viewRepo
    )

import Api
import Api.Data as Api
import Auth
import Components.Button
import Components.GitHub
import Components.GitHubCommit exposing (viewCommitInfo)
import Components.Job exposing (formatJobDuration, getJobStartedAtText, getPlatformText, viewJobDetails, viewJobStatus, viewSimpleJob)
import Components.ListTile
import DateFormat.Relative exposing (relativeTime)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events
import Icons
import RemoteData
import Route exposing (Route)
import Route.Path
import Shared
import Shared.Model
import Svg.Attributes
import Time
import Uuid


viewOwner : Shared.Model.Model -> Api.OwnerWithRepos -> Html msg
viewOwner shared owner =
    div [ class "mb-10" ]
        [ div [ class "flex items-center mb-4 pb-2 border-b border-light dark:border-dark-border" ]
            [ Components.GitHub.viewAvatar
                { username = owner.login
                , size = "md"
                , extraClasses = "mr-2"
                }
            , a [ Route.Path.href (Route.Path.Github_Owner_ { owner = owner.login }), class "text-xl font-bold text-secondary dark:text-dark-text hover:text-primary dark:hover:text-primary transition-colors" ]
                [ text owner.name ]
            , div [ class "ml-2 px-2 py-1 text-xs rounded-full bg-light dark:bg-dark-surface text-secondary dark:text-dark-text-secondary" ]
                [ text
                    (if owner.isUser then
                        "User"

                     else
                        "Organization"
                    )
                ]
            ]
        , div [ class "space-y-4" ]
            (List.map (viewRepo owner.login shared.now) owner.repos)
        ]


viewRepo : String -> Time.Posix -> Api.RepoInfo -> Html msg
viewRepo ownerLogin now repo =
    let
        repoHeader =
            div [ class "flex items-center justify-between" ]
                [ a
                    [ Route.Path.href (Route.Path.Github_Owner__Repo_ { owner = ownerLogin, repo = repo.name })
                    , class "flex items-center hover:text-primary dark:hover:text-primary"
                    ]
                    [ div
                        [ class "font-semibold text-secondary dark:text-dark-text truncate mr-2"
                        ]
                        [ text repo.name ]
                    , if repo.isPrivate then
                        span [ class "text-xs px-2 py-0.5 bg-light dark:bg-dark-surface text-secondary dark:text-dark-text-secondary rounded-full shrink-0" ]
                            [ text "private" ]

                      else
                        span [ class "text-xs px-2 py-0.5 bg-light dark:bg-dark-surface text-secondary dark:text-dark-text-secondary rounded-full shrink-0" ]
                            [ text "public" ]
                    ]
                , case repo.generatePr of
                    Just url ->
                        a
                            [ href url
                            , class "app-link px-3 py-1.5 text-sm bg-white dark:bg-dark-surface/80 rounded-md border border-primary/20 dark:border-primary/30"
                            , target "_blank"
                            ]
                            [ text "View PR" ]

                    Nothing ->
                        text ""
                ]

        repoBody =
            if repo.latestCommit /= Nothing then
                case repo.latestCommit of
                    Just commit ->
                        let
                            commitInfo =
                                viewCommitInfo
                                    { rev = commit.rev
                                    , ref = commit.ref
                                    , message = commit.message
                                    , author = commit.author
                                    , owner = ownerLogin
                                    , repo = repo.name
                                    }

                            jobsView =
                                if List.isEmpty commit.jobs then
                                    text ""

                                else
                                    div [ class "space-y-4" ]
                                        (List.map (viewSimpleJob now) commit.jobs)
                        in
                        [ -- Clickable commit info area
                          a
                            [ Route.Path.href (Route.Path.Github_Owner__Repo__Rev_ { owner = ownerLogin, repo = repo.name, rev = commit.rev })
                            , class "px-5 py-4 mx-1 block hover:bg-gray-50 dark:hover:bg-gray-900/50 transition-all duration-200 cursor-pointer"
                            ]
                            [ commitInfo ]

                        -- Jobs displayed below, within the card padding
                        , div [ class "p-5" ]
                            [ jobsView ]
                        ]

                    Nothing ->
                        []

            else
                [ div
                    [ class "py-4 px-5 text-sm text-gray-500 dark:text-gray-400 italic" ]
                    [ text "No commits yet. "
                    , a
                        [ href "https://devenv.new"
                        , target "_blank"
                        , class "app-link underline hover:no-underline"
                        ]
                        [ text "Start with devenv.new" ]
                    ]
                ]
    in
    div [ class "block" ]
        [ Components.ListTile.new
            |> Components.ListTile.withHeader repoHeader
            |> Components.ListTile.withRows repoBody
            |> Components.ListTile.view
        ]


viewEmptyDashboard : Shared.Model.Model -> Html msg
viewEmptyDashboard shared =
    div [ class "max-w-2xl mx-auto" ]
        [ div [ class "text-center py-16 bg-white dark:bg-dark-surface rounded-2xl border border-gray-200 dark:border-dark-border shadow-xs" ]
            [ div [ class "w-20 h-20 bg-gray-100 dark:bg-gray-800 rounded-full flex items-center justify-center mx-auto mb-6" ]
                [ Icons.github [ Svg.Attributes.class "w-10 h-10 text-gray-500 dark:text-gray-400" ] ]
            , div [ class "text-2xl font-bold text-gray-900 dark:text-white mb-3" ]
                [ text "Welcome to Devenv Cloud!" ]
            , div [ class "text-gray-600 dark:text-gray-400 mb-8 max-w-md mx-auto" ]
                [ text "To get started, install the GitHub App on your repositories." ]
            , a
                [ href
                    (case shared.config of
                        RemoteData.Success config ->
                            "https://github.com/apps/" ++ config.githubAppName ++ "/installations/new"

                        _ ->
                            "#"
                    )
                , target "_blank"
                , class "inline-flex items-center gap-2 px-6 py-3 bg-linear-to-r from-gray-900 to-gray-800 dark:from-white dark:to-gray-100 text-white dark:text-gray-900 rounded-full hover:shadow-lg hover:scale-105 transition-all duration-200 font-medium"
                ]
                [ Icons.github [ Svg.Attributes.class "w-5 h-5" ]
                , text "Install GitHub App"
                , text " →"
                ]
            , div [ class "mt-8 pt-8 border-t border-gray-200 dark:border-gray-800" ]
                [ div [ class "text-sm text-gray-600 dark:text-gray-400 mb-4" ]
                    [ text "Need help getting started?" ]
                , div [ class "flex items-center justify-center gap-6" ]
                    [ a
                        [ href "https://devenv.sh/getting-started/"
                        , target "_blank"
                        , class "text-sm text-primary hover:text-primary-dark dark:text-primary-light dark:hover:text-primary transition-colors font-medium"
                        ]
                        [ text "Read the docs" ]
                    , a
                        [ href "https://github.com/cachix/devenv"
                        , target "_blank"
                        , class "text-sm text-primary hover:text-primary-dark dark:text-primary-light dark:hover:text-primary transition-colors font-medium"
                        ]
                        [ text "View on GitHub" ]
                    ]
                ]
            ]
        ]
