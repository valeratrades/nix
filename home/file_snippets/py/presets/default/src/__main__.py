import sys

from loguru import logger
from typeguard import install_import_hook

# must precede the `src` import — the hook only instruments modules loaded after it
install_import_hook(["src"])
import src


def main():
	logger.remove()
	logger.add(sys.stderr, level="TRACE", colorize=False, filter=lambda r: r["level"].name == "TRACE")
	logger.add(sys.stderr, colorize=True, filter=lambda r: r["level"].no >= 10)

	src.run()


main()
