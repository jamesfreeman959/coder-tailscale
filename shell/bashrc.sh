# shellcheck shell=bash
# Old name of the shell hook, kept so existing ~/.bashrc lines keep working: see rc.sh.
# shellcheck disable=SC1091
. "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/rc.sh"
