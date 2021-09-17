#!/usr/bin/env bash

set -e

for x in {0..7}; do docker build -t "step${x}" -f "step${x}.Dockerfile" .; done