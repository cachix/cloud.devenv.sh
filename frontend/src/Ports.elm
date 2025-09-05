port module Ports exposing (connectSSE, disconnectSSE, exitFullscreen, fullscreenChanged, requestFullscreen, scrollControl, scrollPositionChanged, setupScrollListener, sseConnected, sseError, sseMessages, updateUrlHash, userScrolled)

import Json.Encode as Encode


port connectSSE : { id : String, url : String } -> Cmd msg


port disconnectSSE : String -> Cmd msg



-- Consolidated scroll control port


port scrollControl : { id : String, action : String } -> Cmd msg


port setupScrollListener : String -> Cmd msg


port userScrolled : (Bool -> msg) -> Sub msg


port scrollPositionChanged : ({ scrollTop : Float, scrollHeight : Float, clientHeight : Float } -> msg) -> Sub msg


port sseMessages : (Encode.Value -> msg) -> Sub msg


port sseError : (String -> msg) -> Sub msg


port sseConnected : (() -> msg) -> Sub msg


port updateUrlHash : String -> Cmd msg


port requestFullscreen : String -> Cmd msg


port exitFullscreen : () -> Cmd msg


port fullscreenChanged : (Bool -> msg) -> Sub msg
