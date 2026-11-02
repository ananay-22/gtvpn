#!/bin/sh
contents="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
LD_LIBRARY_PATH="$contents/Libs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
{EXPORTS}exec "$contents/Libs/python/{INTERPRETER}" -m {MODULE}{ARGUMENTS} "$@"
