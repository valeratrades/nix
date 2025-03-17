from typing import Any, Self, Union, Optional, List, Tuple, Callable, TypeVar, Generic  # noqa: F401
from .lib import L  # noqa: F401
from icecream import ic  # noqa: F401

__all__ = ["run"]


def run():
	L.debug("Hello World!")
	ic(L)
