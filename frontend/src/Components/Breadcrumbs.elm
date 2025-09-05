module Components.Breadcrumbs exposing
    ( Breadcrumb
    , Breadcrumbs
    , add
    , forCommit
    , forDashboard
    , forOwner
    , forRepository
    , map
    , new
    , view
    , withAvatar
    , withClass
    , withRoute
    , withRouteAndAvatar
    , withText
    )

import Components.GitHub
import Html exposing (..)
import Html.Attributes exposing (..)
import Icons
import Route.Path
import Svg.Attributes


type Separator
    = Chevron


type alias AvatarConfig =
    { username : String
    , size : String
    , extraClasses : String
    }


type Breadcrumb msg
    = Breadcrumb
        { label : String
        , path : Maybe Route.Path.Path
        , avatar : Maybe AvatarConfig
        }


type Breadcrumbs msg
    = Breadcrumbs
        { items : List (Breadcrumb msg)
        , containerClass : String
        }


new : Breadcrumbs msg
new =
    Breadcrumbs
        { items = []
        , containerClass = "flex items-center text-sm gap-2"
        }


add : String -> Maybe String -> Breadcrumbs msg -> Breadcrumbs msg
add label maybeHref breadcrumbs =
    case maybeHref of
        Just _ ->
            withText label breadcrumbs

        Nothing ->
            withText label breadcrumbs


withText : String -> Breadcrumbs msg -> Breadcrumbs msg
withText text (Breadcrumbs settings) =
    let
        breadcrumb =
            Breadcrumb
                { label = text
                , path = Nothing
                , avatar = Nothing
                }

        updatedItems =
            settings.items ++ [ breadcrumb ]
    in
    Breadcrumbs { settings | items = updatedItems }


withRoute : String -> Route.Path.Path -> Breadcrumbs msg -> Breadcrumbs msg
withRoute text path (Breadcrumbs settings) =
    let
        breadcrumb =
            Breadcrumb
                { label = text
                , path = Just path
                , avatar = Nothing
                }

        updatedItems =
            settings.items ++ [ breadcrumb ]
    in
    Breadcrumbs { settings | items = updatedItems }


withAvatar : String -> AvatarConfig -> Breadcrumbs msg -> Breadcrumbs msg
withAvatar text avatarConfig (Breadcrumbs settings) =
    let
        breadcrumb =
            Breadcrumb
                { label = text
                , path = Nothing
                , avatar = Just avatarConfig
                }

        updatedItems =
            settings.items ++ [ breadcrumb ]
    in
    Breadcrumbs { settings | items = updatedItems }


withRouteAndAvatar : String -> Route.Path.Path -> AvatarConfig -> Breadcrumbs msg -> Breadcrumbs msg
withRouteAndAvatar text path avatarConfig (Breadcrumbs settings) =
    let
        breadcrumb =
            Breadcrumb
                { label = text
                , path = Just path
                , avatar = Just avatarConfig
                }

        updatedItems =
            settings.items ++ [ breadcrumb ]
    in
    Breadcrumbs { settings | items = updatedItems }


withClass : String -> Breadcrumbs msg -> Breadcrumbs msg
withClass customClass (Breadcrumbs settings) =
    Breadcrumbs { settings | containerClass = customClass }


map : (msg1 -> msg2) -> Breadcrumbs msg1 -> Breadcrumbs msg2
map fn (Breadcrumbs settings) =
    let
        mapBreadcrumb : Breadcrumb msg1 -> Breadcrumb msg2
        mapBreadcrumb (Breadcrumb item) =
            Breadcrumb { label = item.label, path = item.path, avatar = item.avatar }
    in
    Breadcrumbs
        { items = List.map mapBreadcrumb settings.items
        , containerClass = settings.containerClass
        }


view : Breadcrumbs msg -> Html msg
view (Breadcrumbs settings) =
    nav [ class settings.containerClass, attribute "aria-label" "Breadcrumb" ]
        (List.intersperse viewSeparator (List.map viewBreadcrumb settings.items))


viewBreadcrumb : Breadcrumb msg -> Html msg
viewBreadcrumb (Breadcrumb item) =
    let
        linkClasses =
            "app-link flex items-center gap-1"

        textClasses =
            "text-gray-800 dark:text-gray-300 font-medium flex items-center gap-1"

        avatarElement =
            case item.avatar of
                Just avatarConfig ->
                    Components.GitHub.viewAvatar avatarConfig

                Nothing ->
                    text ""

        content =
            [ avatarElement, text item.label ]
    in
    case item.path of
        Just path ->
            a
                [ Route.Path.href path
                , class linkClasses
                ]
                content

        Nothing ->
            span [ class textClasses ] content


viewSeparator : Html msg
viewSeparator =
    span [ class "mx-2 text-theme-secondary opacity-60" ]
        [ text "/" ]



-- Factory functions for different page types


forDashboard : Breadcrumbs msg
forDashboard =
    new
        |> withText "Dashboard"


forOwner : { owner : String } -> Breadcrumbs msg
forOwner params =
    let
        ownerAvatarConfig =
            { username = params.owner
            , size = "sm"
            , extraClasses = ""
            }
    in
    new
        |> withRouteAndAvatar params.owner (Route.Path.Github_Owner_ { owner = params.owner }) ownerAvatarConfig


forRepository : { owner : String, repo : String } -> Breadcrumbs msg
forRepository params =
    let
        ownerAvatarConfig =
            { username = params.owner
            , size = "sm"
            , extraClasses = ""
            }
    in
    new
        |> withRouteAndAvatar params.owner (Route.Path.Github_Owner_ { owner = params.owner }) ownerAvatarConfig
        |> withRoute params.repo (Route.Path.Github_Owner__Repo_ { owner = params.owner, repo = params.repo })


forCommit : { owner : String, repo : String, rev : String } -> Breadcrumbs msg
forCommit params =
    let
        ownerAvatarConfig =
            { username = params.owner
            , size = "sm"
            , extraClasses = ""
            }

        shortRev =
            String.left 7 params.rev
    in
    new
        |> withRouteAndAvatar params.owner (Route.Path.Github_Owner_ { owner = params.owner }) ownerAvatarConfig
        |> withRoute params.repo (Route.Path.Github_Owner__Repo_ { owner = params.owner, repo = params.repo })
        |> withText shortRev
