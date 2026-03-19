module Auth exposing (User, onPageLoad, viewCustomPage)

import Auth.Action
import Dict
import Html
import Html.Attributes exposing (..)
import Icons
import RemoteData
import Route exposing (Route)
import Route.Path
import Shared
import Shared.Model
import View exposing (View)


type alias User =
    Shared.Model.User


{-| Called before an auth-only page is loaded.
-}
onPageLoad : Shared.Model -> Route () -> Auth.Action.Action User
onPageLoad shared route =
    case shared.user of
        RemoteData.NotAsked ->
            Auth.Action.loadCustomPage

        RemoteData.Loading ->
            Auth.Action.loadCustomPage

        RemoteData.Success user ->
            if user.betaAccess then
                Auth.Action.loadPageWithUser user

            else
                case route.path of
                    Route.Path.Waitlist ->
                        Auth.Action.loadPageWithUser user

                    _ ->
                        Auth.Action.replaceRoute
                            { path = Route.Path.Waitlist
                            , query = Dict.empty
                            , hash = Nothing
                            }

        _ ->
            -- TODO: we might a 404 page instead, but we would need to handle sign out better.
            -- If this redirects to 404, then as soon as we clean the user on sign out, the user will be shown a 404, instead of getting redirected to home.
            Auth.Action.pushRoute
                { path = Route.Path.Home_
                , query = Dict.empty
                , hash = Nothing
                }


{-| Renders whenever `Auth.Action.loadCustomPage` is returned from `onPageLoad`.
-}
viewCustomPage : Shared.Model -> Route () -> View Never
viewCustomPage shared route =
    { title = "Devenv Cloud - Loading"
    , body =
        [ Html.div [ class "flex h-screen justify-center items-center" ] [ Icons.spinner [] ]
        ]
    }
