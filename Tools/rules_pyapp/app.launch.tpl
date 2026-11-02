#!/bin/sh
set -eu
name='{NAME}'
python='{PYTHON}'
environment='{ENVIRONMENT}'
bundle='{BUNDLE}'
contents="$(cd "$(dirname "$0")/.." && pwd -P)"
resources="$contents/Resources"
root="${GTVPN_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/gtvpn}"
envs="$root/envs"
env="$envs/$environment"
complete="$env/.complete"
interpreter="$env/python/cpython-$python-{INTERP_INFIX}/{PYTHON_BIN}"

discard() {
  if [ -e "$1" ]; then
    chmod -R u+w "$1"
    rm -rf "$1"
  fi
}

pip_install() {
  "$resources/uv" pip install \
    --python "$interpreter" \
    --break-system-packages \
    --require-hashes \
    --index-strategy unsafe-first-match \
    --compile-bytecode \
    "$@" \
    -r "$resources/requirements_lock.txt"
}

install_environment() {
  UV_CACHE_DIR="$root/packages/uv"
  UV_NO_CONFIG=1
  UV_NO_PROGRESS=1
  UV_PYTHON_INSTALL_DIR="$env/python"
  export UV_CACHE_DIR UV_NO_CONFIG UV_NO_PROGRESS UV_PYTHON_INSTALL_DIR
  if [ "$bundle" = wheels ]; then
    unset UV_PYTHON_CACHE_DIR
    "$resources/uv" python install --no-bin --mirror "file://$resources/interpreter" "$python"
    pip_install --offline --no-index --find-links "$resources/wheels"
  else
    UV_PYTHON_CACHE_DIR="$root/packages/python"
    export UV_PYTHON_CACHE_DIR
    "$resources/uv" python install --no-bin "$python"
    pip_install
  fi
}

if [ ! -f "$complete" ]; then
  mkdir -p "$envs"
  exec 9>"$env.lock"
  flock 9
  if [ ! -f "$complete" ]; then
    discard "$env"
    trap 'discard "$env"' EXIT
    echo "$name: creating environment $env" >&2
    mkdir "$env"
    (install_environment)
    : >"$complete"
    trap - EXIT
  fi
  exec 9>&-
fi

{LIBVAR}="$contents/Libs${{LIBVAR}:+:${LIBVAR}}"
PYTHONPATH="$resources/python"
PYTHONNOUSERSITE=1
PYTHONSAFEPATH=1
export {LIBVAR} PYTHONPATH PYTHONNOUSERSITE PYTHONSAFEPATH
unset PYTHONHOME RUNFILES_DIR RUNFILES_MANIFEST_FILE
exec "$interpreter" -c 'import runpy, sys
sys.argv[:2] = sys.argv[1:2]
runpy._run_module_as_main("{MODULE}", alter_argv=False)' "$name" "$@"
