import src
from loguru import logger
from typeguard import install_import_hook
import sys


def main():
	install_import_hook(["indicators_bot", "__main__", "nautilus_utils"])
	logger.remove()
	logger.add(sys.stderr, level="TRACE", colorize=False, filter=lambda r: r["level"].name == "TRACE")
	logger.add(sys.stderr, colorize=True, filter=lambda r: r["level"].no >= 10)


	src.run()


main()
