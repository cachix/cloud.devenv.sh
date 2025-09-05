module Layouts.Main exposing (Model, Msg(..), Props, layout, map)

import Api.Data exposing (Account)
import Auth
import Components.Breadcrumbs exposing (Breadcrumbs)
import Components.Button
import Components.Dropdown as Dropdown
import Components.Footer
import Components.GitHub
import Effect exposing (Effect)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Icons
import Layout exposing (Layout)
import Oidc.Model
import RemoteData
import Route exposing (Route)
import Route.Path
import Shared
import Shared.Model exposing (Theme(..))
import Shared.Msg
import Svg.Attributes
import Url
import View exposing (View)


type alias Props contentMsg =
    { breadcrumbs : Breadcrumbs contentMsg
    , buttons : List (Html contentMsg)
    , user : Maybe Auth.User
    , shared : Shared.Model.Model
    }


map : (msg1 -> msg2) -> Props msg1 -> Props msg2
map fn props =
    { breadcrumbs = Components.Breadcrumbs.map fn props.breadcrumbs
    , buttons = List.map (Html.map fn) props.buttons
    , user = props.user
    , shared = props.shared
    }


layout : Props contentMsg -> Shared.Model -> Route () -> Layout () Model Msg contentMsg
layout props shared route =
    Layout.new
        { init = init
        , update = update
        , view = view props route
        , subscriptions = subscriptions
        }



-- MODEL


type alias Model =
    { accountDropdownOpen : Bool
    , mobileMenuOpen : Bool
    }


init : () -> ( Model, Effect Msg )
init _ =
    ( { accountDropdownOpen = False
      , mobileMenuOpen = False
      }
    , Effect.none
    )



-- UPDATE


type Msg
    = ToggleDropdown Bool
    | ToggleMobileMenu
    | CloseMobileMenu
    | SignIn
    | SignOut
    | ToggleTheme


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        ToggleDropdown state ->
            ( { model | accountDropdownOpen = state }
            , Effect.none
            )

        ToggleMobileMenu ->
            ( { model | mobileMenuOpen = not model.mobileMenuOpen }
            , Effect.none
            )

        CloseMobileMenu ->
            ( { model | mobileMenuOpen = False }
            , Effect.none
            )

        SignIn ->
            ( model, Effect.signIn )

        SignOut ->
            ( model
            , Effect.signOut
            )

        ToggleTheme ->
            ( model
            , Effect.toggleTheme
            )


subscriptions : Model -> Sub Msg
subscriptions model =
    Sub.none



-- VIEW


view : Props contentMsg -> Route () -> { toContentMsg : Msg -> contentMsg, content : View contentMsg, model : Model } -> View contentMsg
view props route { toContentMsg, model, content } =
    let
        headerContent =
            div [ class "flex-2" ]
                [ Components.Breadcrumbs.view props.breadcrumbs ]
    in
    { title = "Devenv Cloud - " ++ content.title
    , body =
        [ Html.div
            [ class "theme-map page min-h-screen flex flex-col dark:bg-dark-bg" ]
            [ div [ class "" ] [ viewHeader props model route toContentMsg ]
            , div [ class "flex flex-col container mx-auto px-4 pt-12 max-w-4xl text-theme grow" ]
                [ div [ class "flex flex-wrap gap-2 items-end mb-6" ]
                    [ headerContent
                    , div [ class "flex-1 flex flex justify-start sm:justify-end col-span-3" ]
                        props.buttons
                    ]
                , div [] content.body
                ]
            , Components.Footer.view
            ]
        ]
    }


viewHeader : Props contentMsg -> Model -> Route () -> (Msg -> contentMsg) -> Html contentMsg
viewHeader props model route toContentMsg =
    let
        navButton title to =
            a
                [ class "app-link hover:cursor-pointer"
                , classList [ ( "font-black", to == route.url.path ) ]
                , href to
                ]
                [ text title ]

        navigation =
            [-- navButton "Dashboard" (Route.Path.toString Route.Path.Home_)
            ]

        guestButtons =
            case route.path of
                Route.Path.Home ->
                    -- On the landing page, check if user is actually authenticated
                    case props.shared.user of
                        RemoteData.Success _ ->
                            -- Show "Go to Dashboard" button for authenticated users
                            div [ class "flex gap-2" ]
                                [ Components.Button.new
                                    { label = "Go to dashboard"
                                    , icon = Nothing
                                    , action = Components.Button.Href "/"
                                    }
                                    |> Components.Button.view
                                ]

                        _ ->
                            -- Show login buttons for logged-out users
                            div [ class "flex gap-4" ]
                                [ Components.Button.new
                                    { label = "Log in"
                                    , icon = Nothing
                                    , action = Components.Button.Click (toContentMsg SignIn)
                                    }
                                    |> Components.Button.view
                                , Components.Button.new
                                    { label = "Sign up"
                                    , icon = Nothing
                                    , action = Components.Button.Click (toContentMsg SignIn)
                                    }
                                    |> Components.Button.view
                                ]

                _ ->
                    -- On other pages, show login buttons
                    div [ class "flex gap-4" ]
                        [ Components.Button.new
                            { label = "Log in"
                            , icon = Nothing
                            , action = Components.Button.Click (toContentMsg SignIn)
                            }
                            |> Components.Button.withSize Components.Button.Small
                            |> Components.Button.view
                        , Components.Button.new
                            { label = "Sign up"
                            , icon = Nothing
                            , action = Components.Button.Click (toContentMsg SignIn)
                            }
                            |> Components.Button.withSize Components.Button.Small
                            |> Components.Button.view
                        ]

        themeToggleButton =
            button
                [ class "p-2 text-secondary dark:text-dark-text-secondary rounded-full hover:text-primary dark:hover:text-primary focus:outline-hidden transition-colors ml-2"
                , onClick (toContentMsg ToggleTheme)
                ]
                [ if props.shared.theme == Dark then
                    Icons.sunIcon [ Svg.Attributes.class "w-5 h-5" ]

                  else
                    Icons.moonIcon [ Svg.Attributes.class "w-5 h-5" ]
                ]
    in
    nav
        [ class "container max-w-4xl p-4 text-secondary font-semibold flex flex-wrap items-center justify-between mx-auto dark:text-dark-text-secondary"
        ]
        [ div
            [ class "items-center flex justify-between mx-auto w-full"
            ]
            [ a [ class "flex h-8", Route.Path.href Route.Path.Home_ ]
                [ img [ class "logo-light", src "/logo.webp" ] []
                , img [ class "logo-dark", src "/logo-dark.webp" ] []
                ]
            , div [ class "grow hidden md:flex items-end justify-around" ]
                navigation
            , div [ class "hidden md:flex items-center justify-end space-x-2" ]
                [ themeToggleButton
                , case props.user of
                    Nothing ->
                        guestButtons

                    Just userInfo ->
                        viewUser userInfo model toContentMsg
                ]
            , div [ class "md:hidden flex items-center space-x-2" ]
                [ themeToggleButton
                , button
                    [ class "p-2 text-secondary dark:text-dark-text-secondary rounded-lg hover:bg-light dark:hover:bg-dark-surface focus:outline-hidden"
                    , onClick (toContentMsg ToggleMobileMenu)
                    ]
                    [ Icons.menu [ Svg.Attributes.class "w-6 h-6" ] ]
                ]
            ]
        , div
            [ class "fixed inset-0 bg-black bg-opacity-50 z-40 md:hidden transition-opacity duration-300 ease-in-out"
            , classList [ ( "hidden", not model.mobileMenuOpen ), ( "opacity-0", not model.mobileMenuOpen ) ]
            , onClick (toContentMsg CloseMobileMenu)
            ]
            []
        , div
            [ class "fixed right-0 top-0 h-full w-64 bg-white dark:bg-dark-surface z-50 md:hidden transition-transform duration-300 ease-in-out transform shadow-xl dark:shadow-black/50"
            , classList [ ( "translate-x-full", not model.mobileMenuOpen ) ]
            ]
            [ div [ class "p-4" ]
                [ div [ class "flex justify-between items-center mb-5" ]
                    [ h3 [ class "text-lg font-bold dark:text-dark-text" ] [ text "Menu" ]
                    , button
                        [ class "p-2 rounded-lg hover:bg-light dark:hover:bg-dark-border focus:outline-hidden"
                        , onClick (toContentMsg CloseMobileMenu)
                        ]
                        [ Icons.menu [ Svg.Attributes.class "w-6 h-6" ] ]
                    ]
                , div [ class "flex flex-col space-y-4" ]
                    (List.concat
                        [ navigation
                        , [ hr [ class "my-2 border-light dark:border-dark-border" ] [] ]
                        , case props.user of
                            Nothing ->
                                case route.path of
                                    Route.Path.Home ->
                                        -- On the landing page, check if user is actually authenticated
                                        case props.shared.user of
                                            RemoteData.Success _ ->
                                                -- Show "Go to Dashboard" button for authenticated users
                                                [ div [ class "flex flex-col space-y-2" ]
                                                    [ Components.Button.new
                                                        { label = "Go to Dashboard"
                                                        , icon = Nothing
                                                        , action = Components.Button.Href "/"
                                                        }
                                                        |> Components.Button.view
                                                    ]
                                                ]

                                            _ ->
                                                -- Show login buttons for logged-out users
                                                [ div [ class "flex flex-col space-y-2" ]
                                                    [ Components.Button.new
                                                        { label = "Log in"
                                                        , icon = Nothing
                                                        , action = Components.Button.Click (toContentMsg SignIn)
                                                        }
                                                        |> Components.Button.view
                                                    , Components.Button.new
                                                        { label = "Sign up"
                                                        , icon = Nothing
                                                        , action = Components.Button.Click (toContentMsg SignIn)
                                                        }
                                                        |> Components.Button.view
                                                    ]
                                                ]

                                    _ ->
                                        -- On other pages, show login buttons
                                        [ div [ class "flex flex-col space-y-2" ]
                                            [ Components.Button.new
                                                { label = "Log in"
                                                , icon = Nothing
                                                , action = Components.Button.Click (toContentMsg SignIn)
                                                }
                                                |> Components.Button.view
                                            , Components.Button.new
                                                { label = "Sign up"
                                                , icon = Nothing
                                                , action = Components.Button.Click (toContentMsg SignIn)
                                                }
                                                |> Components.Button.view
                                            ]
                                        ]

                            Just userInfo ->
                                [ viewMobileUser userInfo toContentMsg ]
                        ]
                    )
                ]
            ]
        ]


viewMobileUser : Oidc.Model.UserInfo -> (Msg -> contentMsg) -> Html contentMsg
viewMobileUser userInfo toContentMsg =
    let
        avatarUsername =
            Maybe.withDefault "" userInfo.preferred_username
    in
    div [ class "flex flex-col" ]
        [ div [ class "flex items-center px-4 py-2" ]
            [ case userInfo.preferred_username of
                Just username ->
                    Components.GitHub.viewAvatar
                        { username = username
                        , size = "md"
                        , extraClasses = "mr-2"
                        }

                Nothing ->
                    img
                        [ class "h-8 w-8 rounded-full mr-2"
                        , src (getUserAvatarUrl userInfo)
                        , alt "User avatar"
                        ]
                        []
            , span [ class "font-medium" ]
                [ text (Maybe.withDefault "User" userInfo.given_name) ]
            ]
        , a
            [ class "px-4 py-2 mt-2 text-red hover:bg-light dark:hover:bg-dark-border rounded-md"
            , onClick (toContentMsg SignOut)
            ]
            [ Icons.logOut [ Svg.Attributes.class "inline mr-2 w-4" ]
            , text "Log out"
            ]
        ]


viewUser : Oidc.Model.UserInfo -> Model -> (Msg -> contentMsg) -> Html contentMsg
viewUser userInfo model toContentMsg =
    let
        dropdownItem icon name route =
            a [ class "block px-3 py-1.5 text-xs app-link hover:underline hover:cursor-pointer whitespace-nowrap", route ]
                [ icon [ Svg.Attributes.class "inline w-4 h-4 mr-2" ], text name ]

        toggleButton =
            div [ class "flex items-center" ]
                [ case userInfo.preferred_username of
                    Just username ->
                        Components.GitHub.viewAvatar
                            { username = username
                            , size = "sm"
                            , extraClasses = "mr-2"
                            }

                    Nothing ->
                        img
                            [ class "h-6 w-6 rounded-full mr-2"
                            , src (getUserAvatarUrl userInfo)
                            , alt "User avatar"
                            ]
                            []
                , span [ class "text-xs whitespace-normal break-normal" ]
                    [ text (Maybe.withDefault "" userInfo.given_name) ]
                ]

        dropdownItems =
            [ -- TODO: dropdownItem Icons.userCircle "Profile" (Route.Path.href Route.Path.Profile)
              -- TODO: dropdownItem Icons.creditCard02 "Plan & Billing" (Route.Path.href Route.Path.Billing)
              dropdownItem Icons.logOut "Log out" (onClick (toContentMsg SignOut))
            ]
    in
    Dropdown.dropdown
        { identifier = "account-dropdown"
        , toggleButton = toggleButton
        , toggleButtonClass = Dropdown.standardDropdownStyle
        , items = dropdownItems
        , onToggle = ToggleDropdown >> toContentMsg
        , isOpen = model.accountDropdownOpen
        }


getUserAvatarUrl : Oidc.Model.UserInfo -> String
getUserAvatarUrl userInfo =
    -- Use GitHub avatar for all users
    case userInfo.preferred_username of
        Just username ->
            Components.GitHub.getAvatarUrl username

        Nothing ->
            -- Fallback to generating avatar using name
            let
                name =
                    Maybe.withDefault "User" userInfo.given_name
            in
            "https://ui-avatars.com/api/?name=" ++ name ++ "&background=F7D15D&color=4A3E3D"


