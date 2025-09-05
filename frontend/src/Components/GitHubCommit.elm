module Components.GitHubCommit exposing
    ( formatCommitMessage
    , viewAuthor
    , viewBranch
    , viewCommitInfo
    , viewCommitMessage
    , viewRevBranch
    , viewRevision
    )

{-| Component for rendering GitHub commits consistently.
-}

import Components.GitHub
import Components.Label as Label
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Icons
import Route
import Route.Path
import Svg.Attributes


{-| Formats a commit message by displaying only the first line
and adding an ellipsis if there are more lines.
-}
formatCommitMessage : String -> String
formatCommitMessage message =
    case String.split "\n" message of
        [] ->
            ""

        firstLine :: rest ->
            if List.isEmpty rest then
                firstLine

            else
                firstLine ++ " ..."


{-| Renders a commit message with consistent styling,
showing only the first line with ellipsis if there are more lines.
-}
viewCommitMessage : { message : String, owner : String, repo : String, rev : String } -> Html msg
viewCommitMessage { message, owner, repo, rev } =
    a
        [ Route.Path.href (Route.Path.Github_Owner__Repo__Rev_ { owner = owner, repo = repo, rev = rev })
        , class "app-link font-semibold"
        ]
        [ text (formatCommitMessage message) ]


{-| Renders a revision (commit hash) with standard formatting.
Takes the full hash and owner/repo for linking to GitHub.
-}
viewRevision : { rev : String, owner : String, repo : String } -> Html msg
viewRevision { rev, owner, repo } =
    Label.view
        (Label.new { text = String.left 7 rev }
            |> Label.asLink ("https://github.com/" ++ owner ++ "/" ++ repo ++ "/commit/" ++ rev)
            |> Label.withAttributes [ target "_blank" ]
            |> Label.withClass "rounded-l hover:underline"
        )


{-| Renders a branch name with standard formatting.
Takes the branch name and owner/repo for linking to GitHub.
-}
viewBranch : { ref : String, owner : String, repo : String } -> Html msg
viewBranch { ref, owner, repo } =
    Label.view
        (Label.new { text = ref }
            |> Label.asLink ("https://github.com/" ++ owner ++ "/" ++ repo ++ "/tree/" ++ ref)
            |> Label.withAttributes [ target "_blank" ]
            |> Label.withClass "rounded-r hover:underline"
        )


{-| Renders a full rev@branch label combining the revision and branch.
-}
viewRevBranch : { rev : String, ref : String, owner : String, repo : String } -> Html msg
viewRevBranch { rev, ref, owner, repo } =
    Label.view
        (Label.new { text = "" }
            |> Label.asCombined
                [ Label.new { text = String.left 7 rev }
                    |> Label.asLink ("https://github.com/" ++ owner ++ "/" ++ repo ++ "/commit/" ++ rev)
                    |> Label.withAttributes [ target "_blank" ]
                    |> Label.withClass "rounded-l hover:underline"
                , Label.new { text = "@" }
                    |> Label.withClass "px-0"
                , Label.new { text = ref }
                    |> Label.asLink ("https://github.com/" ++ owner ++ "/" ++ repo ++ "/tree/" ++ ref)
                    |> Label.withAttributes [ target "_blank" ]
                    |> Label.withClass "rounded-r hover:underline"
                ]
        )


{-| Renders a GitHub author with standard formatting.
-}
viewAuthor : { author : String, owner : String, repo : String, rev : String } -> Html msg
viewAuthor { author, owner, repo, rev } =
    a
        [ Route.Path.href (Route.Path.Github_Owner__Repo__Rev_ { owner = owner, repo = repo, rev = rev })
        , class "flex items-center gap-2 shrink-0 text-secondary dark:text-dark-text hover:text-primary dark:hover:text-primary transition-colors"
        ]
        [ Components.GitHub.viewAvatar
            { username = author
            , size = "sm"
            , extraClasses = ""
            }
        , span [ class "whitespace-nowrap" ] [ text ("@" ++ author) ]
        ]


{-| Renders complete commit info in a single line with revision, branch and message.
All components are properly linked to GitHub.
-}
viewCommitInfo : { rev : String, ref : String, message : String, author : String, owner : String, repo : String } -> Html msg
viewCommitInfo { rev, ref, message, author, owner, repo } =
    div [ class "flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2" ]
        [ div [ class "flex items-center gap-2 min-w-0" ]
            [ viewAuthor { author = author, owner = owner, repo = repo, rev = rev }
            , span [ class "truncate" ]
                [ viewCommitMessage { message = message, owner = owner, repo = repo, rev = rev } ]
            ]
        , div [ class "flex items-center shrink-0 text-sm font-mono" ]
            [ a
                [ href ("https://github.com/" ++ owner ++ "/" ++ repo ++ "/commit/" ++ rev)
                , target "_blank"
                , class "app-link flex items-center"
                ]
                [ Icons.github [ Svg.Attributes.class "mr-1 w-4 h-4" ]
                , text (String.left 7 rev)
                ]
            , span [ class "mx-0.5 text-gray-500 dark:text-gray-500" ] [ text "@" ]
            , a
                [ href ("https://github.com/" ++ owner ++ "/" ++ repo ++ "/tree/" ++ ref)
                , target "_blank"
                , class "app-link"
                ]
                [ text ref ]
            ]
        ]
