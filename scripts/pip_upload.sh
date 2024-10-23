#!/bin/sh

rm -rf ./dist ./build
python -m build
twine upload ./dist/* -u __token__ -p $PYPI_KEY
