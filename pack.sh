#!/bin/bash
# Create release tarballs of tlp-gentoo-additions used in the ebuilds.
#
# Usage: "<this script> <version>"
# See <this script> --help for options.
#
# Example usage:
# ./pack.sh 0.3.7.9-r1
# (or run "tar cjf ./local/dist/tlp-gentoo-additions-<PVR>.tar.bz2 ./gentoo")
#

# bash-specific features in use: array, [[ <test> ]], ...
if [ -z "${BASH_VERSION:-}" ]; then
   echo "interpreter is not bash - script will likely malfunction" 1>&2
fi

set -o nounset
set +o history

# constant str PROJECT_DIR
#  project root directory
PROJECT_DIR=`dirname "${0}"`
case "${PROJECT_DIR}" in
   /*)
      true
   ;;
   .)
      PROJECT_DIR="${PWD}"
   ;;
   ./*)
      PROJECT_DIR="${PWD}/${PROJECT_DIR#./}"
   ;;
   *)
      PROJECT_DIR="${PWD}/${PROJECT_DIR}"
   ;;
esac
readonly PROJECT_DIR

# constant str PROJECT_NAME
#  (the project name)
PROJECT_NAME="${PROJECT_DIR##*/}"
readonly PROJECT_NAME="${PROJECT_NAME#tlp-}"

# constant str PROJECT_TARBALL_NAME_PREFIX
#  this string will be the prefix for all
#  tarball file names
readonly PROJECT_TARBALL_NAME_PREFIX='tlp-'

# constant str PACKLIB
#  shell script file that contains the functions required for packing.
readonly PACKLIB="${PROJECT_DIR}/include/packer.sh"

# constant str TARBALL_ROOT_DIRECTORY is aliased %PROJECT_DIR
#  %PACKLIB does not know about %PROJECT_DIR
readonly TARBALL_ROOT_DIRECTORY="${PROJECT_DIR}"

# str PVR inherits %TLPVER
#  tlp version + gentoo revision we're packing for
#  * this can be any string *
PVR="${TLPVER:-}"

# settings for %PACKLIB
COMPRESS=bzip2
IMAGE_DIR="${PROJECT_DIR}/local/dist"
OVERWRITE=
DEBUG=

# @noreturn die ( [msg:=""], [code:=1] ), raises exit()
#  Prints an error message to stderr
#  and exits with %code afterwards.
#
die() {
   if [[ "${1:-}" ]]; then
      echo "died: ${1}" 1>&2
   else
      echo "died." 1>&2
   fi
   exit ${2:-1}
}
# --- end of die (...) ---

# @wrapper __err__ (<ignored>)
#  Restores the ERR trap and calls die().
__err__() {
   trap - ERR
   if [[ ${#FUNCNAME[@]} -gt 1 ]]; then
      echo "functrace = ${FUNCNAME[*]}" 1>&2
      die "unknown error in function ${FUNCNAME[1]/main/(main)}"
   else
      # only true if sourced by interactive shell
      die "unknown error in __main__"
   fi
}
# --- end of __err__ (...) ---

# @noreturn print_usage ( [exit_code:=64] )
#
#  Prints the usage message and exits afterwards with %exit_code.
#
print_usage() {
   local -r SCRIPT_NAME="${0##*/}" OPTS='[option [option...]]'

   echo "${SCRIPT_NAME} - create tarball(s) for distributing ${PROJECT_NAME}

Usage:
* ${SCRIPT_NAME} ${OPTS} <PVR>,
  where PVR must start with a digit
* TLPVER=\"<PVR>\" ${SCRIPT_NAME} ${OPTS}

options:
--force (-f) -- overwrite existing tarballs
--help  (-h) -- this message
--debug      -- debug mode" 1>&2
   exit ${1:-64}
}
# --- end of print_usage (...) ---

# void pack_generic_subdir (
#    [relpath:=<auto>],
#    **PROJECT_TARBALL_NAME_PREFIX,
#    **PROJECT_NAME,
#    **PVR
# )
#
#  Packer function for a directory in %PROJECT_DIR.
#  Subdirectory name defaults to %FUNCNAME[1] with
#  the 'pack_' prefix removed.
#
#  @TODO: move this to %PACKLIB.
#
pack_generic_subdir() {
   local relpath="${1:-}"
   if [[ -z "${relpath}" ]]; then
      relpath="${FUNCNAME[1]#pack_}"
   fi
   # "./" becomes "./<relpath>/"
   local TAROPTS_EXTRA=( '--transform' "s,^\.\/,./${relpath}/," )
   dotar "${PROJECT_TARBALL_NAME_PREFIX}${PROJECT_NAME}-${PVR:?}"
}
# --- end of pack_generic_subdir (...) ---

# void pack_gentoo (...)
#  Pack %PROJECT_DIR/gentoo.
#
pack_gentoo() { pack_generic_subdir; }
# --- end of pack_gentoo (...) ---

# void read_argv ( *argv ), raises exit() via print_usage()
#
#  Parse %argv.
#
read_argv() {
   local -i doshift=1
   while [[ $# -gt 0 ]]; do
      case "${1?}" in
         '')
            true
         ;;
         --force|-f)
            OVERWRITE=y
         ;;
         --force=*)
            OVERWRITE=${1#--force=}
         ;;
         --debug)
            trap __err__ ERR
            DEBUG=y
         ;;
         --help|-h)
            print_usage 0
         ;;
         [0-9]*)
            if [[ "${PVR:-}" ]]; then
               echo "!!! PVR already set ( PVR=${PVR}, PVR_NEW=${1}" 1>&2
               print_usage
            else
               PVR="${1}"
            fi
         ;;
         *)
            echo "!!! unknown arg '${1}'" 1>&2
            print_usage
         ;;
      esac

      shift ${doshift} || exit
      doshift=1
   done
   if [[ -z "${PVR:-}" ]]; then
      echo "!!! PVR is not set" 1>&2
      print_usage
   fi
   return 0
}
# --- end of read_argv (...) ---


# @implicit int main (...)
#
#  See print_usage() or call this script with --help.
#
read_argv "$@"
source ${PROJECT_DIR}/include/packer.sh --as-lib || exit
pack gentoo
