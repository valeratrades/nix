import src
from loguru import logger


def main():
	logger.remove()
	logger.add(lambda msg: print(msg, end=""), level="DEBUG", diagnose=True, backtrace=True)

	src.run()


main()
