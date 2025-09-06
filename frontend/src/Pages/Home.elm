module Pages.Home exposing (Model, Msg, page, viewLanding)

import Components.LandingLayout
import Effect exposing (Effect)
import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Icons
import Page exposing (Page)
import Route exposing (Route)
import Shared
import Svg.Attributes
import View exposing (View)


page : Shared.Model -> Route () -> Page Model Msg
page shared route =
    Page.new
        { init = init
        , update = update
        , subscriptions = subscriptions
        , view = view shared route
        }


type alias Model =
    {}


init : () -> ( Model, Effect Msg )
init _ =
    ( {}
    , Effect.none
    )


type Msg
    = SignIn
    | ToggleTheme


update : Msg -> Model -> ( Model, Effect Msg )
update msg model =
    case msg of
        SignIn ->
            ( model, Effect.signIn )

        ToggleTheme ->
            ( model, Effect.toggleTheme )


subscriptions : Model -> Sub Msg
subscriptions _ =
    Sub.none


view : Shared.Model -> Route () -> Model -> View Msg
view shared route model =
    { title = "Devenv Cloud - CI for Nix"
    , body =
        [ Components.LandingLayout.view
            { onSignIn = SignIn
            , onToggleTheme = ToggleTheme
            , theme = shared.theme
            , user = shared.user
            , route = route
            }
            [ viewLanding SignIn ]
        ]
    }


viewLanding : msg -> Html msg
viewLanding signInMsg =
    div [ class "container mx-auto py-6 px-4" ]
        [ -- Hero Section
          div [ class "min-h-[60vh] flex flex-col justify-center text-center py-20" ]
            [ h1 [ class "text-5xl md:text-6xl lg:text-7xl font-black text-secondary dark:text-dark-text mb-6 tracking-tight" ]
                [ text "Replace GitHub Actions"
                , br [] []
                , text "with devenv & Nix"
                ]
            , p [ class "text-xl md:text-2xl text-secondary/70 dark:text-dark-text-secondary mb-6 max-w-2xl mx-auto font-light" ]
                [ text "Your devenv.nix is both your dev environment and CI config." ]
            , div [ class "flex flex-col sm:flex-row items-center justify-center gap-4" ]
                [ button
                    [ class "inline-flex items-center gap-2 px-10 py-5 bg-linear-to-r from-gray-900 to-gray-800 dark:from-white dark:to-gray-100 text-white dark:text-gray-900 rounded-full hover:shadow-2xl hover:scale-105 transition-all duration-200 font-semibold text-xl cursor-pointer"
                    ]
                    [ Icons.github [ Svg.Attributes.class "w-6 h-6 text-white dark:text-gray-900" ]
                    , text "Coming Soon →"
                    ]
                , a
                    [ href "https://devenv.sh"
                    , target "_blank"
                    , class "px-8 py-4 text-secondary dark:text-dark-text-secondary hover:text-primary transition-colors font-medium text-lg"
                    ]
                    [ text "Learn more" ]
                ]
            ]

        -- Key Features - Simple Grid
        , div [ class "py-24" ]
            [ div [ class "grid md:grid-cols-3 gap-8 max-w-6xl mx-auto" ]
                [ featureCard
                    { icon = "⚡"
                    , title = "No extra setup"
                    , description = "Your devenv.nix replaces workflow files"
                    }
                , featureCard
                    { icon = "🔄"
                    , title = "Local = CI"
                    , description = "Test CI scripts locally with devenv test"
                    }
                , featureCard
                    { icon = "🔒"
                    , title = "Minimal environment"
                    , description = "Hermetic builds with Nix guarantees"
                    }
                , featureCard
                    { icon = "🖥️"
                    , title = "Multi-platform native"
                    , description = "Linux x86_64, ARM64 & macOS M1/M2/M3"
                    }
                , featureCard
                    { icon = "🚀"
                    , title = "Lightning-fast caching"
                    , description = "Pre-built environments using Cachix"
                    }
                , featureCard
                    { icon = "🛡️"
                    , title = "VM isolation"
                    , description = "Each job runs in a fresh VM"
                    }
                ]
            ]

        -- Code Example - Minimal
        , div [ class "py-24" ]
            [ div [ class "max-w-4xl mx-auto" ]
                [ div [ class "bg-white dark:bg-gray-900 rounded-2xl shadow-2xl border border-gray-200 dark:border-gray-800 overflow-hidden" ]
                    [ div [ class "bg-linear-to-r from-gray-100 to-gray-50 dark:from-gray-800 dark:to-gray-900 px-6 py-3 border-b border-gray-200 dark:border-gray-800" ]
                        [ div [ class "flex items-center gap-2" ]
                            [ div [ class "w-3 h-3 rounded-full bg-red-500" ] []
                            , div [ class "w-3 h-3 rounded-full bg-yellow-500" ] []
                            , div [ class "w-3 h-3 rounded-full bg-green-500" ] []
                            , span [ class "ml-3 text-sm font-mono text-gray-600 dark:text-gray-400" ] [ text "devenv.nix" ]
                            ]
                        ]
                    , pre [ class "p-6 lg:p-8 overflow-x-auto" ]
                        [ code [ class "text-sm lg:text-base text-gray-800 dark:text-gray-200 font-mono leading-relaxed" ]
                            [ text """{ pkgs, lib, config, ... }:
let
  # https://devenv.sh/cloud/
  github = config.cloud.ci.github;
in {
  # https://devenv.sh/basics/
  packages = [ pkgs.cargo-watch ];

  # https://devenv.sh/languages/
  languages = {
    rust.enable = true;
    python = {
      enable = true;
      venv.enable = true;
      uv.enable = true;
    };
  };

  # https://devenv.sh/processes/
  processes = {
    myapp.exec = "cargo run -x";
  };

  # https://devenv.sh/services/
  services = {
    # run postgresql only locally
    postgresql.enable = !config.cloud.enable;
  };

  # https://devenv.sh/git-hooks/
  git-hooks = {
    hooks.rustfmt.enable = true;
    # run pre-commit hooks only on changes
    fromRef = github.base_ref or null;
    toRef = github.ref or null;
  };

  # https://devenv.sh/tasks/
  tasks = {
    "myapp:tests" = {
      after = [ "devenv:enterTest" ];
      exec = "cargo test";
    };
    # run code review agent on main branch
    "myapp:code-reviewer" = lib.mkIf (github.branch == "main") {
      exec = "claude @code-reviewer";
    };
  };

  # https://devenv.sh/outputs/
  outputs = {
    # package Rust app using Nix
    myapp = config.language.rust.import ./. {};
  };
}
"""
                            ]
                        ]
                    ]
                , p [ class "text-center mt-8 text-gray-600 dark:text-gray-300 font-medium" ]
                    [ text "devenv.nix - Your entire CI pipeline in one file" ]
                ]
            ]

        -- Comparison section
        , div [ class "py-24 max-w-6xl mx-auto" ]
            [ h2 [ class "text-3xl md:text-4xl font-bold text-center text-gray-900 dark:text-white mb-16" ]
                [ text "Why replace GitHub Actions?" ]
            , div [ class "grid md:grid-cols-2 gap-8" ]
                [ div [ class "bg-red-50 dark:bg-red-950/30 rounded-2xl p-8 border border-red-200 dark:border-red-900" ]
                    [ h3 [ class "text-xl font-semibold text-red-700 dark:text-red-400 mb-6 flex items-center gap-2" ]
                        [ div [ class "w-8 h-8 bg-red-100 dark:bg-red-900/50 rounded-full flex items-center justify-center text-red-600 dark:text-red-400" ]
                            [ text "✕" ]
                        , text "GitHub Actions"
                        ]
                    , div [ class "space-y-3 text-red-500 dark:text-red-400" ]
                        [ comparisonItem "YAML configuration files"
                        , comparisonItem "Different environment locally vs CI"
                        , comparisonItem "Slow container startup times (2-5 min)"
                        , comparisonItem "Complex matrix build syntax"
                        , comparisonItem "Can't test workflows locally"
                        , comparisonItem "Debugging via commit & push"
                        , comparisonItem "No dependency caching between runs"
                        ]
                    ]
                , div [ class "bg-green-50 dark:bg-green-950/30 rounded-2xl p-8 border border-green-200 dark:border-green-900" ]
                    [ h3 [ class "text-xl font-semibold text-green-700 dark:text-green-400 mb-6 flex items-center gap-2" ]
                        [ div [ class "w-8 h-8 bg-green-100 dark:bg-green-900/50 rounded-full flex items-center justify-center text-green-600 dark:text-green-400" ]
                            [ text "✓" ]
                        , text "Devenv Cloud"
                        ]
                    , div [ class "space-y-3 text-green-500 dark:text-green-400" ]
                        [ comparisonItem "Pure Nix configuration"
                        , comparisonItem "Identical local & CI environments"
                        , comparisonItem "Sub-second VM starts + cached envs"
                        , comparisonItem "Declarative multi-platform support"
                        , comparisonItem "Test with 'devenv test' locally"
                        , comparisonItem "Debug in your local devenv shell"
                        ]
                    ]
                ]
            ]

        -- CTA Section
        , div [ class "text-center py-32" ]
            [ h2 [ class "text-3xl md:text-4xl font-bold text-gray-900 dark:text-white mb-8" ]
                [ text "Ready to simplify your CI?" ]
            , button
                [ class "inline-flex items-center gap-2 px-10 py-5 bg-linear-to-r from-gray-900 to-gray-800 dark:from-white dark:to-gray-100 text-white dark:text-gray-900 rounded-full hover:shadow-2xl hover:scale-105 transition-all duration-200 font-semibold text-xl cursor-pointer"
                ]
                [ Icons.github [ Svg.Attributes.class "w-6 h-6 text-white dark:text-gray-900" ]
                , text "Coming Soon"
                , text " →"
                ]
            ]
        ]


featureCard : { icon : String, title : String, description : String } -> Html msg
featureCard { icon, title, description } =
    div [ class "group bg-white dark:bg-dark-surface rounded-xl p-6 border border-gray-200 dark:border-dark-border hover:shadow-lg dark:hover:shadow-xl dark:hover:shadow-black/10 hover:border-gray-300 dark:hover:border-gray-700 transition-all duration-200" ]
        [ div [ class "w-12 h-12 bg-gray-100 dark:bg-gray-800 rounded-lg flex items-center justify-center mb-4 group-hover:scale-110 transition-transform" ]
            [ span [ class "text-2xl" ] [ text icon ] ]
        , h3 [ class "text-lg font-semibold text-gray-900 dark:text-white mb-2" ] [ text title ]
        , p [ class "text-sm text-gray-600 dark:text-gray-400 leading-relaxed" ] [ text description ]
        ]


comparisonItem : String -> Html msg
comparisonItem item =
    div [ class "flex items-start gap-2" ]
        [ span [ class "mt-0.5" ] [ text "•" ]
        , span [ class "text-gray-800 dark:text-gray-50" ] [ text item ]
        ]
