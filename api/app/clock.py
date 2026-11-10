"""The current time, injected so that date rules (streaks) are testable.

``create_app`` receives a Clock; routers read it once per request and pass the instant down.
"""

import datetime as dt
from collections.abc import Callable

# Returns a timezone-aware instant.
type Clock = Callable[[], dt.datetime]


def system_clock() -> dt.datetime:
    return dt.datetime.now(dt.UTC)
