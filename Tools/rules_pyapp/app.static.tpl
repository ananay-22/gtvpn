#!/bin/sh
set -eu
name='{NAME}'
contents="$(cd "$(dirname "$0")/.." && pwd -P)"
PYTHONPATH="$contents/Resources/python"
PYTHONNOUSERSITE=1
PYTHONSAFEPATH=1
export PYTHONPATH PYTHONNOUSERSITE PYTHONSAFEPATH
unset PYTHONHOME RUNFILES_DIR RUNFILES_MANIFEST_FILE
exec "$contents/{INTERPRETER}" -c 'import runpy, sys
sys.argv[:2] = sys.argv[1:2]
runpy._run_module_as_main("{MODULE}", alter_argv=False)' "$name" "$@"
