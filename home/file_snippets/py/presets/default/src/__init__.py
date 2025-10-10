from typing import Any, Self, Union, Optional, List, Tuple, Callable, TypeVar, Generic  # noqa: F401
from icecream import ic  # noqa: F401
from loguru import logger

__all__ = ["run"]


def run():
	logger.debug("Hello World!")
	ic("loguru logger is active")
