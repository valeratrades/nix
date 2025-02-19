from typing import Any, Self, Union, Optional, List, Tuple, Callable, TypeVar, Generic  # noqa: F401
from .lib import L  # noqa: F401

__all__ = ["run"]

try:
    from icecream import ic  # noqa: F401
except ImportError:  # Graceful fallback if IceCream isn't installed.
    ic = lambda *a: None if not a else (a[0] if len(a) == 1 else a)  # noqa


def run():
    L.debug("Hello World!")
    ic(L)
