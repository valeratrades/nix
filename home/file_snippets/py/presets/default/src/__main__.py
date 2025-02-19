import src
import logging


def main():
    logging.basicConfig(
        level=logging.DEBUG, format="%(asctime)s - %(levelname)s - %(message)s"
    )
    src.L = logging.getLogger(__name__)

    src.run()


main()
