module Icons exposing (..)

-- https://flowbite.com/icons/

import Svg exposing (Svg)
import Svg.Attributes


account : List (Svg.Attribute msg) -> Svg.Svg msg
account attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-6 h-6 text-gray-600 dark:text-white"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "currentColor"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.fillRule "evenodd"
            , Svg.Attributes.d "M12 20a7.966 7.966 0 0 1-5.002-1.756l.002.001v-.683c0-1.794 1.492-3.25 3.333-3.25h3.334c1.84 0 3.333 1.456 3.333 3.25v.683A7.966 7.966 0 0 1 12 20ZM2 12C2 6.477 6.477 2 12 2s10 4.477 10 10c0 5.5-4.44 9.963-9.932 10h-.138C6.438 21.962 2 17.5 2 12Zm10-5c-1.84 0-3.333 1.455-3.333 3.25S10.159 13.5 12 13.5c1.84 0 3.333-1.455 3.333-3.25S13.841 7 12 7Z"
            , Svg.Attributes.clipRule "evenodd"
            ]
            []
        ]


logOut : List (Svg.Attribute msg) -> Svg msg
logOut attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-6 h-6 text-gray-600 dark:text-dark-text"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M16 12H4m12 0-4 4m4-4-4-4m3-4h2a3 3 0 0 1 3 3v10a3 3 0 0 1-3 3h-2"
            ]
            []
        ]


spinner : List (Svg.Attribute msg) -> Svg msg
spinner attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-8 h-8 text-gray-100 animate-spin dark:text-dark-border fill-primary"
         , Svg.Attributes.viewBox "0 0 100 101"
         , Svg.Attributes.fill "none"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.d "M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z"
            , Svg.Attributes.fill "currentColor"
            ]
            []
        , Svg.node "path"
            [ Svg.Attributes.d "M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z"
            , Svg.Attributes.fill "currentFill"
            ]
            []
        ]


search : List (Svg.Attribute msg) -> Svg msg
search attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-6 h-6 text-gray-600 dark:text-dark-text"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "m21 21-3.5-3.5M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0Z"
            ]
            []
        ]


github : List (Svg.Attribute msg) -> Svg msg
github attributes =
    let
        defaultAttributes =
            [ Svg.Attributes.class "text-gray-600 dark:text-dark-text"
            , Svg.Attributes.width "24"
            , Svg.Attributes.height "24"
            , Svg.Attributes.fill "currentColor"
            , Svg.Attributes.viewBox "0 0 24 24"
            ]
    in
    Svg.node "svg"
        (defaultAttributes ++ attributes)
        [ Svg.node "path"
            [ Svg.Attributes.fillRule "evenodd"
            , Svg.Attributes.d "M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z"
            , Svg.Attributes.clipRule "evenodd"
            ]
            []
        ]


menu : List (Svg.Attribute msg) -> Svg msg
menu attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-6 h-6 text-gray-600 dark:text-dark-text"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M3 6h18M3 12h18M3 18h18"
            ]
            []
        ]


discord : List (Svg.Attribute msg) -> Svg msg
discord attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-6 h-6 text-gray-600 dark:text-dark-text"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "currentColor"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.d "M19.27 5.33C17.94 4.71 16.5 4.26 15 4a.09.09 0 0 0-.07.03c-.18.33-.39.76-.53 1.09a16.09 16.09 0 0 0-4.8 0c-.14-.34-.35-.76-.54-1.09-.01-.02-.04-.03-.07-.03-1.5.26-2.93.71-4.27 1.33-.01 0-.02.01-.03.02-2.72 4.07-3.47 8.03-3.1 11.95 0 .02.01.04.03.05 1.8 1.32 3.53 2.12 5.24 2.65.03.01.06 0 .07-.02.4-.55.76-1.13 1.07-1.74.02-.04 0-.08-.04-.09-.57-.22-1.11-.48-1.64-.78-.04-.02-.04-.08-.01-.11.11-.08.22-.17.33-.25.02-.02.05-.02.07-.01 3.44 1.57 7.15 1.57 10.55 0 .02-.01.05-.01.07.01.11.09.22.17.33.26.04.03.04.09-.01.11-.52.31-1.07.56-1.64.78-.04.01-.05.06-.04.09.32.61.68 1.19 1.07 1.74.03.02.06.02.09.01 1.72-.53 3.45-1.33 5.25-2.65.02-.01.03-.03.03-.05.44-4.53-.73-8.46-3.1-11.95-.01-.01-.02-.02-.04-.02zM8.52 14.91c-1.03 0-1.89-.95-1.89-2.12s.84-2.12 1.89-2.12c1.06 0 1.9.96 1.89 2.12 0 1.17-.84 2.12-1.89 2.12zm6.97 0c-1.03 0-1.89-.95-1.89-2.12s.84-2.12 1.89-2.12c1.06 0 1.9.96 1.89 2.12 0 1.17-.83 2.12-1.89 2.12z"
            ]
            []
        ]


sunIcon : List (Svg.Attribute msg) -> Svg msg
sunIcon attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-6 h-6 text-gray-600 dark:text-dark-text"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M12 4V2m0 20v-2m8-8h2M2 12h2m13.657-5.657L19.07 4.93M4.93 19.07l1.414-1.414m0-11.314L4.93 4.93m14.14 14.14-1.414-1.414M12 17a5 5 0 1 0 0-10 5 5 0 0 0 0 10Z"
            ]
            []
        ]


moonIcon : List (Svg.Attribute msg) -> Svg msg
moonIcon attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-6 h-6 text-gray-600 dark:text-dark-text"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79Z"
            ]
            []
        ]


eye : List (Svg.Attribute msg) -> Svg msg
eye attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-6 h-6 text-gray-600 dark:text-dark-text"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M2.036 12.322a1.012 1.012 0 0 1 0-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178Z"
            ]
            []
        , Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z"
            ]
            []
        ]


chevronRight : List (Svg.Attribute msg) -> Svg msg
chevronRight attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-6 h-6 text-gray-600 dark:text-dark-text"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M9 5l6 7-6 7"
            ]
            []
        ]


exclamation : List (Svg.Attribute msg) -> Svg msg
exclamation attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-6 h-6"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126ZM12 15.75h.007v.008H12v-.008Z"
            ]
            []
        ]


computer : List (Svg.Attribute msg) -> Svg msg
computer attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4 text-gray-600 dark:text-gray-400"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M9 17.25v1.007a3 3 0 0 1-.879 2.122L7.5 21h9l-.621-.621A3 3 0 0 1 15 18.257V17.25m6-12V15a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 15V5.25m18 0A2.25 2.25 0 0 0 18.75 3H5.25A2.25 2.25 0 0 0 3 5.25m18 0V12a2.25 2.25 0 0 1-2.25 2.25H5.25A2.25 2.25 0 0 1 3 12V5.25"
            ]
            []
        ]


clock : List (Svg.Attribute msg) -> Svg msg
clock attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4 text-gray-600 dark:text-gray-400"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
            ]
            []
        ]


hourglass : List (Svg.Attribute msg) -> Svg msg
hourglass attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4 text-gray-600 dark:text-gray-400"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M6.75 3.653v.057a3.97 3.97 0 0 0 1.107 2.755l2.467 2.467a1.588 1.588 0 0 1 0 2.248L7.857 13.644A3.97 3.97 0 0 0 6.75 16.399v.057m10.5-12.803v.057a3.97 3.97 0 0 1-1.107 2.755l-2.467 2.467a1.588 1.588 0 0 0 0 2.248l2.467 2.464a3.971 3.971 0 0 1 1.107 2.755v.057M4.5 3.75h15M4.5 20.25h15"
            ]
            []
        ]


cpu : List (Svg.Attribute msg) -> Svg msg
cpu attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4 text-gray-600 dark:text-gray-400"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M8 9h8m-8 3h8m-8 3h8M3 12h.01M7 12h.01M11 12h.01M15 12h.01M19 12h.01M7 16h.01M11 16h.01M15 16h.01M7 8h.01M11 8h.01M15 8h.01M3 8h.01M19 8h.01M3 16h.01M19 16h.01M4 20V4h16v16H4z"
            ]
            []
        ]


memory : List (Svg.Attribute msg) -> Svg msg
memory attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4 text-gray-600 dark:text-gray-400"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M20 14V7a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v7m16 0v3a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2v-3m16 0H4m2-5h.01M9 9h.01M13 9h.01M17 9h.01"
            ]
            []
        ]


calendar : List (Svg.Attribute msg) -> Svg msg
calendar attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4 text-gray-600 dark:text-gray-400"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M6.75 3v2.25M17.25 3v2.25M3 18.75V7.5a2.25 2.25 0 012.25-2.25h13.5A2.25 2.25 0 0121 7.5v11.25m-18 0A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75m-18 0v-7.5A2.25 2.25 0 015.25 9h13.5A2.25 2.25 0 0121 11.25v7.5"
            ]
            []
        ]



-- Job status icons


success : List (Svg.Attribute msg) -> Svg msg
success attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M9 12.75L11.25 15 15 9.75M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            ]
            []
        ]


failed : List (Svg.Attribute msg) -> Svg msg
failed attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M9.75 9.75l4.5 4.5m0-4.5l-4.5 4.5M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            ]
            []
        ]


running : List (Svg.Attribute msg) -> Svg msg
running attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "393"
         , Svg.Attributes.height "300"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 393 300"
         ]
            ++ attributes
        )
        [ Svg.node "style"
            []
            [ Svg.text """
                .fade {
                  animation: fadeAway 3s ease-in-out infinite;
                }
                @keyframes fadeAway {
                  0% { opacity: 1; }
                  50% { opacity: 0; }
                  100% { opacity: 1; }
                }
            """
            ]
        , Svg.node "path"
            [ Svg.Attributes.class "fade"
            , Svg.Attributes.style "animation-delay: 0s"
            , Svg.Attributes.d "M250.822 31.7073C232.183 31.7073 217.073 46.8173 217.073 65.4564V114.634H300V65.4564C300 46.8173 284.89 31.7073 266.251 31.7073H250.822Z"
            , Svg.Attributes.fill "#425C82"
            ]
            []
        , Svg.node "path"
            [ Svg.Attributes.class "fade"
            , Svg.Attributes.style "animation-delay: 0.375s"
            , Svg.Attributes.d "M309.756 124.39V207.317H392.683V158.139C392.683 139.5 377.573 124.39 358.934 124.39H309.756Z"
            , Svg.Attributes.fill "#425C82"
            ]
            []
        , Svg.node "path"
            [ Svg.Attributes.class "fade"
            , Svg.Attributes.style "animation-delay: 0.75s"
            , Svg.Attributes.d "M217.073 124.39V207.317H300V124.39H217.073Z"
            , Svg.Attributes.fill "#425C82"
            ]
            []
        , Svg.node "path"
            [ Svg.Attributes.class "fade"
            , Svg.Attributes.style "animation-delay: 1.125s"
            , Svg.Attributes.d "M309.756 217.073V300H358.934C377.573 300 392.683 284.89 392.683 266.251V217.073H309.756Z"
            , Svg.Attributes.fill "#425C82"
            ]
            []
        , Svg.node "path"
            [ Svg.Attributes.class "fade"
            , Svg.Attributes.style "animation-delay: 1.5s"
            , Svg.Attributes.d "M217.073 217.073V300H300V217.073H217.073Z"
            , Svg.Attributes.fill "#101010"
            ]
            []
        , Svg.node "path"
            [ Svg.Attributes.class "fade"
            , Svg.Attributes.style "animation-delay: 1.875s"
            , Svg.Attributes.d "M124.39 217.073V300H206.098V217.073H124.39Z"
            , Svg.Attributes.fill "#101010"
            ]
            []
        , Svg.node "path"
            [ Svg.Attributes.class "fade"
            , Svg.Attributes.style "animation-delay: 2.25s"
            , Svg.Attributes.d "M64.2371 217.073C45.5979 217.073 30.4879 232.183 30.4879 250.822V266.251C30.4879 284.89 45.5979 300 64.2371 300H113.415V217.073H64.2371Z"
            , Svg.Attributes.fill "#101010"
            ]
            []
        , Svg.node "path"
            [ Svg.Attributes.class "fade"
            , Svg.Attributes.style "animation-delay: 2.625s"
            , Svg.Attributes.d "M157.643 124.39C139.278 124.39 124.39 139.5 124.39 158.139V207.317H206.098V124.39H157.643Z"
            , Svg.Attributes.fill "#101010"
            ]
            []
        , Svg.node "path"
            [ Svg.Attributes.fillRule "evenodd"
            , Svg.Attributes.clipRule "evenodd"
            , Svg.Attributes.d "M311.683 114.953V94.1645V67.2897C311.683 42.5144 291.568 22.4299 266.755 22.4299H250.341C225.528 22.4299 205.414 42.5143 205.414 67.2897V92.7363V115.166H182.95H154.651C131.389 115.166 112.531 133.995 112.531 157.222V185.477V207.907H90.0678H64.5829C41.321 207.907 22.4636 226.736 22.4636 249.963V271.961C22.4636 282.733 26.5195 292.559 33.1895 300H6.40782C2.30187 291.522 0 282.01 0 271.961V249.963C0 214.349 28.9147 185.477 64.5829 185.477H90.0678V157.222C90.0678 121.608 118.983 92.7363 154.651 92.7363H182.95V67.2897C182.95 30.1266 213.122 0 250.341 0H266.755C303.974 0 334.146 30.1267 334.146 67.2897V114.953H311.683Z"
            , Svg.Attributes.fill "#101010"
            ]
            []
        ]


queued : List (Svg.Attribute msg) -> Svg msg
queued attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z"
            ]
            []
        ]


cancelled : List (Svg.Attribute msg) -> Svg msg
cancelled attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636"
            ]
            []
        ]


timedOut : List (Svg.Attribute msg) -> Svg msg
timedOut attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M12 9v3.75m-9.303 3.376c-.866 1.5.217 3.374 1.948 3.374h14.71c1.73 0 2.813-1.874 1.948-3.374L13.949 3.378c-.866-1.5-3.032-1.5-3.898 0L2.697 16.126zM12 15.75h.007v.008H12v-.008z"
            ]
            []
        ]


expand : List (Svg.Attribute msg) -> Svg msg
expand attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15"
            ]
            []
        ]


compress : List (Svg.Attribute msg) -> Svg msg
compress attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M9 9L3.75 3.75m4.5 4.5v-4.5m0 4.5h-4.5M15 9l5.25-5.25M15 9v-4.5m0 4.5h4.5M9 15l-5.25 5.25m4.5-4.5v4.5m0-4.5h-4.5M15 15l5.25 5.25M15 15v4.5m0-4.5h4.5"
            ]
            []
        ]


skipped : List (Svg.Attribute msg) -> Svg msg
skipped attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M21 7.5l-9-5.25L3 7.5m18 0l-9 5.25m9-5.25v9l-9 5.25M3 7.5l9 5.25M3 7.5v9l9 5.25m0-9v9"
            ]
            []
        ]


arrowPath : List (Svg.Attribute msg) -> Svg msg
arrowPath attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"
            ]
            []
        ]


arrowLeft : List (Svg.Attribute msg) -> Svg msg
arrowLeft attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-6 h-6 text-gray-800 dark:text-white"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M5 12h14M5 12l4-4m-4 4 4 4"
            ]
            []
        ]



-- Three dots menu icon (ellipsis)


dotsVertical : List (Svg.Attribute msg) -> Svg msg
dotsVertical attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M12 5v.01M12 12v.01M12 19v.01M12 6a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2zm0 7a1 1 0 110-2 1 1 0 010 2z"
            ]
            []
        ]



-- X mark icon for cancellations


xMark : List (Svg.Attribute msg) -> Svg msg
xMark attributes =
    Svg.node "svg"
        ([ Svg.Attributes.class "w-4 h-4"
         , Svg.Attributes.width "24"
         , Svg.Attributes.height "24"
         , Svg.Attributes.fill "none"
         , Svg.Attributes.viewBox "0 0 24 24"
         ]
            ++ attributes
        )
        [ Svg.node "path"
            [ Svg.Attributes.stroke "currentColor"
            , Svg.Attributes.strokeLinecap "round"
            , Svg.Attributes.strokeLinejoin "round"
            , Svg.Attributes.strokeWidth "2"
            , Svg.Attributes.d "M6 18L18 6M6 6l12 12"
            ]
            []
        ]
