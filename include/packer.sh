#!/bin/bash -u
#  Tarball creation; meant for usage in scripts.

# @FIXME namespace

# @typedef simple_bool
#  true if value has non-zero length, else false

# constant str ROOT inherits %TARBALL_ROOT_DIRECTORY or %PWD
#  base directory for certain operations
readonly ROOT="${TARBALL_ROOT_DIRECTORY:-${PWD}}"

echo "$ROOT"
exit 1

# str DEVNULL
: ${DEVNULL:=/dev/null}

# str COMPRESS
#  compression method,
#   any-of {
#      gzip  => { z, gz*, tar.gz, tgz },
#      bzip2 => { j, bz*, tar.bz*, tbz* },
#      none  => { },
#   }
: ${COMPRESS=}

# simple_bool OVERWRITE
#  overwrite tarball files that exist?
: ${OVERWRITE=}
# simple_bool DEBUG
#  print some extra information
: ${DEBUG=}

# simple_bool NOPACK
#  this script will not pack anything if true
#: ${NOPACK=}

# list<str> TAROPTS_EXTRA
#  additional options for tar
#[[ -z "${TAROPTS_EXTRA[*]:-}" ]] || TAROPTS_EXTRA=()

# str IMAGE_DIR
#  tarball destination directory
case "${IMAGE_DIR:-}" in
   /*)
      true
   ;;
   '.'|'')
      IMAGE_DIR="${ROOT%/}/images"
   ;;
   ./*)
      IMAGE_DIR="${ROOT%/}/${IMAGE_DIR#./}"
   ;;
   *)
      IMAGE_DIR="${ROOT%/}/${IMAGE_DIR#/}"
   ;;
esac


#ifndef die
if ! LC_ALL=C LANG=C command -V die 2>${DEVNULL?} | \
   grep -qx -- 'die is a function'
then
# @noreturn die ( [msg:=""], [code:=1] ), raises exit()
#
#  Prints an error message to stderr
#  and exits with %code afterwards.
#
echo "define die()"
die() {
   if [[ "${1:-}" ]]; then
      echo "died: ${1}" 1>&2
   else
      echo "died." 1>&2
   fi
   exit ${2:-1}
}
# --- end of die (...) ---
fi
#endif

# int _run ( *argv, **DEBUG )
#
#  Print %argv to stdout if %DEBUG is set to 'y'.
#  Run %argv afterwards.
#
_run() {
   [[ -z "${DEBUG:-}" ]] || echo "run: $*"
   "$@"
}
# --- end of _run (...) ---

# @wrapper __dotar_image_trap__ (<ignored>)
#
#  Removes %image and restores the INT TERM EXIT signals.
#  Has to be called during dotar's image creation step.
#
__dotar_image_trap__() {
   local rc=$?
   # restore signals now so that successive signals (hit ctrl+c twice,...)
   # do not trigger this function again
   trap - INT TERM EXIT
   if [[ -z "${image:-}" ]]; then
      die "${FUNCNAME}(): invalid context - %image is not set."
   elif [[ -e "${image}" ]]; then
      rm -v "${image}" || echo "rm returned $? - ${image} still exists." 1>&2
   fi
   return ${rc}
}
# --- end of __dotar_image_trap__ (...) ---

# int dotar (
#    [tarball_name:=<auto>],
#    **COMPRESS, **IMAGE_DIR,
#    **EXCLUDE, **TAROPTS_EXTRA,
#    **ROOT, **OVERWRITE
# )
#
#  Actually creates the desired tarball (
#   %IMAGE_DIR/%tarball_name.<%file_extension>
#  ) using whatever has been configured.
#
#  %tarball_name defaults to the name of the calling
#  function with the 'pack_' prefix removed.
#
#  %file_extension depends on %COMPRESS.
#
#  Returns 70 if the tarball already exists
#  and %OVERWRITE is set, else tar's return code.
#
dotar() {
   local name="${1:-}"
   [[ "$name" ]] || name="${FUNCNAME[1]#pack_}"

   local rc=255

   # determine compression settings (%COMPRESS)
   # * %comp   - compression arg for tar
   # * %comext - file extension for the tarball
   local comp compext
   case "${COMPRESS:-}" in
      z|gz*|tar.gz)
         comp=z
         compext='tar.gz'
      ;;
      tgz)
         comp=z
         compext='tgz'
      ;;
      j|bz*|tar.bz*)
         comp=j
         compext='tar.bz2'
      ;;
      tbz*)
         comp=j
         compext='tbz2'
      ;;
      '')
         comp=
         compext='tar'
      ;;
      *)
         die "COMPRESS=${COMPRESS} is unknown."
      ;;
   esac

   # tarball file (%IMAGE_DIR)
   local image="${IMAGE_DIR%/}/${name}${compext:+.}${compext#.}"

   # construct the tar command (%EXCLUDE, %TAROPTS_EXTRA)
   local argv=( 'tar' 'c' './' '-f' "${image}" )
   [[ -z "${comp?}" ]] || argv+=( "-${comp}" )

   if [[ ${#EXCLUDE[@]} -gt 0 ]]; then
      argv+=( "${EXCLUDE[@]}" )
   fi

   if [[ "${TAROPTS_EXTRA[*]:-}" ]]; then
      argv+=( "${TAROPTS_EXTRA[@]}" )
   fi

   # finally start packing (%PWD or %ROOT, %OVERWRITE)

   [[ -d "${image%/*}" ]] || mkdir -vp "${image%/*}" || \
      die "cannot create image dir '${image%/*}'"

   echo "Packing <root>/${PWD#${ROOT}/} into ${image#$ROOT/} ... " 1>&2

   if [[ ( -z "${OVERWRITE:-}" ) && ( -e "${image}" ) ]]; then
      echo "Error: tarball already exists and overwriting is disabled." 1>&2
      return 70
   elif [[ ! -e "${image}" ]] || rm -v -- "${image}"; then
      trap __dotar_image_trap__ INT TERM EXIT

      rc=0
      _run "${argv[@]}" || rc=$?
      trap - INT TERM EXIT

   else
      die "${image} still exists (cannot be deleted?)."
   fi

   return ${rc}
}
# --- end of dotar (...) ---

# void tar_exclude ( *file )
#
#  Add zero or more files to the current %EXCLUDE list.
#
tar_exclude() {
   local x;
   for x; do
      x="${x#./}"
      EXCLUDE+=( '--exclude' "./${x#/}" )
   done
}
# --- end of tar_exclude (...) ---

# void tar_exclude_dir ( *dir )
#
#  Add zero or more directories to the current %EXCLUDE list.
#
tar_exclude_dir() {
   local x;
   for x; do
      x="${x#./}"
      EXCLUDE+=( '--exclude' "./${x#/}/*" )
   done
}
# --- end of tar_exclude_dir (...) ---

# void into ( [dirname:=""] ), raises die()
#
#  Alias for cd %ROOT/%dirname.
#  Dies if cd returns a non-zero code.
#
into() {
   local dest="${1:-}"
   if [[ "${dest}" ]]; then
      dest="${ROOT}/${dest#/}"
   else
      dest="${ROOT}"
   fi
   cd "${dest}" || die "into ( '${1:-}' => '${dest}' ), cd returned $?."
}
# --- end of into (...) ---

# @{true,undefined} pack ( *target, [**PACK_DIE:=exit] ), raises %PACK_DIE()
#
#  Packs zero or more targets by
#  calling pack_<t> for each t in %target.
#
#  Dies on first failure by calling %PACK_DIE(<pack_target return code>).
#  So, theoretically, it is possible to "recover" from failure by setting
#  PACK_DIE=true (or a specific onerror function).
#
# !!! Do not call pack_<target> directly unless 100% sure.
#
pack() {
   local target
   local EXCLUDE=()
   for target; do
      # using a subshell,
      #  propagating any changes (vars, working directory, ...)
      #  from pack_<target> functions is not allowed
      #
      # !!! This also means that exit($?) has to be called explicitly here.
      #
      (
         if [[ -e "${ROOT}/${target}" ]]; then
            into "${target}"
         else
            into
         fi && \
         pack_${target} || die "pack_${target} failed"
      ) || ${PACK_DIE:-exit} $?

      # finally reset %EXCLUDE
      EXCLUDE=()
   done
}
# --- end of pack (...) ---


# @implicit int main ( *target, **NOPACK, **PACK_TARGETS )
#  Packs the given targets, either those listed in %target
#  or the ones in %PACK_TARGETS.
#
#  Returns 64 if no targets given, else passes the return
#  value of the pack() function.
#
#  Does nothing if %NOPACK is set or %1 is '--as-lib'.
#
if [[ ( -z "${NOPACK:-}" ) && ( "${1:-}" != '--as-lib' ) ]]; then
   if [[ $# -gt 0 ]]; then
      pack "$@"
   elif [[ -n "${PACK_TARGETS:-}" ]]; then
      pack "${PACK_TARGETS[@]}"
   else
      echo "Usage:
* ${0##*/} target [target..]
* PACK_TARGETS=\"target [target...]\" ${0##*/}" 1>&2
      exit 64
   fi
fi
