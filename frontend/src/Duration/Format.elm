module Duration.Format exposing (formatHMS)

import Duration
import Time


{-| Format a duration between two timestamps as "Xh Xm Xs"
-}
formatHMS : Time.Posix -> Time.Posix -> String
formatHMS startTime endTime =
    let
        startMillis =
            Time.posixToMillis startTime

        endMillis =
            Time.posixToMillis endTime

        durationMillis =
            endMillis - startMillis

        duration =
            Duration.milliseconds (toFloat durationMillis)

        hours =
            floor (Duration.inHours duration)

        hoursInMs =
            Duration.hours (toFloat hours)

        remainderAfterHours =
            if Duration.inMilliseconds hoursInMs <= Duration.inMilliseconds duration then
                Duration.milliseconds (Duration.inMilliseconds duration - Duration.inMilliseconds hoursInMs)

            else
                Duration.milliseconds 0

        minutes =
            floor (Duration.inMinutes remainderAfterHours)

        minutesInMs =
            Duration.minutes (toFloat minutes)

        remainderAfterMinutes =
            if Duration.inMilliseconds minutesInMs <= Duration.inMilliseconds remainderAfterHours then
                Duration.milliseconds (Duration.inMilliseconds remainderAfterHours - Duration.inMilliseconds minutesInMs)

            else
                Duration.milliseconds 0

        seconds =
            floor (Duration.inSeconds remainderAfterMinutes)

        hourText =
            if hours > 0 then
                String.fromInt hours ++ "h "

            else
                ""

        minuteText =
            if minutes > 0 || hours > 0 then
                String.fromInt minutes ++ "m "

            else
                ""

        secondText =
            String.fromInt seconds ++ "s"
    in
    hourText ++ minuteText ++ secondText
