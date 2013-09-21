#!/bin/sh
# Multicall script that edits TLP's files.
# Currently, it is able to relocate TLP's config file and the tpacpi-bat
# script.
#
# Valid script names:
# * tlp_configure*,        -- configure TLP's files for a specific target
#    configure*
# * tlp_relocate_conffile* -- just change the location where TLP expects to
#    relocate_conffile*        find its config file
#
# ----------------------------------------------------------------------------
#
# Initially written by Andre Erdmann <dywi@mailerd.de> on 2nd Januar, 2013.
# This script is provided "as is". Consider it as public domain.
#
# ----------------------------------------------------------------------------

set -u
if [ -n "${BASH_VERSION:-}" ]; then
   set -o posix
   set +o history
   set +o braceexpand
fi

readonly _IFS_DEFAULT="${IFS}"
readonly _IFS_NEWLINE='
'

# chars that are allowed in file names (full paths),
#  used as char class (sed)
readonly FILENAME_CHARS='-$./a-zA-Z0-9'

readonly ERR=1
readonly ERR_USAGE=64

# external programs {
: ${X_SED:=sed}
: ${X_HEAD:=head}
: ${X_GREP:=grep}
: ${X_FIND:=find}
readonly X_SED X_HEAD X_GREP X_FIND
# }

# other vars {
: ${DEFAULT_CONFFILE:=/etc/default/tlp}
: ${CONFFILE:=}

: ${TPACPIBAT:=}

: ${TLP_ROOT:=${PWD}}

: ${VERBOSE=y}

: ${CONFFILE_EDIT_BLACKLIST:=Makefile}
# }


## generic functions {

# ---
# @noreturn die ( [msg], [code] ), raises exit(%code)
#
#  Prints %msg to stderr (if not empty)
#  and exits afterwards with status %code.
#
# arguments:
# * msg  -- error message, defaults to ""
# * code -- exit code, defaults to 1
#
die() {
   [ -z "${1:-}" ] || echo "${1}" 1>&2
   [ -z "${2:-}" ] && exit ${ERR} || exit ${2}
}
# --- end of die (...) ---

# ---
# @true msg_info ( msg )
#
#  Prints %msg to stdout if %VERBOSE is set.
#
msg_info() {
   [ -z "${VERBOSE:-}" ] || echo "$*"
}
# --- end of msg_info (...) ---

# ---
# @true msg_debug ( msg )
#
#  Prints %msg to stdout if %DEBUG is set.
#
msg_debug() {
   [ -z "${DEBUG:-}" ] || echo "$*"
}
# --- end of msg_debug (...) ---

# ---
# int editvar_shell ( varname, new_value, shell_file, [add_comment] )
#
#  Edits variable (and constant) declarations in shell (bash/dash) files.
#  This function has some restrictions, most notably it expects that
#  only one variable is defined per line.
#  Adds a "# edited: was <old_value>" comment at the end of each edited line
#  if %edit_comment evaluates to true.
#
#  Returns sed's exit code or %ERR_USAGE (= not enough args).
#
#
# arguments:
# * varname     -- name of the variable that whose value will be edited,
#                   must not be empty
# * new_value   -- new value for %varname
# * shell_file  -- file to edit, has to be an existing file
# * add_comment -- add comments described above if this arg is set
#                   (and has non-zero length)
#
editvar_shell() {
   [ ${#} -ge 3 ] || return ${ERR_USAGE}
   # "FIXME": also edits var="...' statements (but this should
   #           be a minor issue)
   #  => use a more unambiguous regex if required
   #
   # regex groups:
   # 1: keyword    -- "readonly", "declare" or empty (whitespace preserved)
   # 2: varname    -- "varname="
   # 3: quote char -- ", ' or empty
   # 4: old value  --
   # 5: quote char -- see 3
   # 6: remainder  -- only whitespace and end-of-line comments allowed (will be discarded)
   #
   local _common_regex="s,^(\s*readonly\s*|\s*declare\s*|\s*)(${1:?}=)\
([\'\"]|)([${FILENAME_CHARS}]+)([\'\"]|)(\s*|\s*#..*)$,\1\2\3${2}\5"

   if [ -n "${4:-}" ]; then
      ${X_SED} -r -e "${_common_regex} # edited: was \"\4\"," -i "${3:?}"
   else
      ${X_SED} -r -e "${_common_regex}," -i "${3:?}"
   fi
}
# --- end of editvar_shell (...) ---

# ---
# int _in ( *list, **kw )
#  Returns true if %kw is in %list, else false. %kw must not be empty.
#
#  Example usage: "kw=word _in a b c d e f"
#
_in() {
   : ${kw:?}
   # unpack $1 as list if less than two list items supplied (noop if $# is 0)
   [ ${#} -gt 1 ] || set -- $*
   local iter
   for iter; do
      [ -z "${iter}" ] || [ "${iter}" != "${kw}" ] || return 0
   done
   return 1
}
# --- end of _in (...) ---

# ---
# int is_shell_file ( file )
#
#  Returns true if %file is a shell file (first line contains 'sh'),
#  else false.
#
is_shell_file() { ${X_HEAD} -n 1 "${1:?}" | ${X_GREP} -qs -- sh; }
# --- end of is_shell_file (...) ---

# ---
# int is_protected_file ( file )
#
#  Returns true if %file is protected, e.g. if it is a git file.
#
is_protected_file() {
   case "${1:?}" in
      */.git/*|.git/*)
         return 0
      ;;
      */debian/*|debian/*)
         return 0
      ;;
      */gentoo/*|gentoo/*)
         return 0
      ;;
      *)
         return 1
      ;;
   esac
}
# --- end of is_protected_file (...) ---

## } // generic functions

## (TLP-)specific functions {

# @true tlp_set_conffile (
#    *file,
#    **CONFFILE,
#    **DEFAULT_CONFFILE,
#    **TLP_ROOT,
#    [**CONFFILE_EDIT_BLACKLIST],
#    [**TLP_CONFFILE_IGNORE_NOEXIST]
# ), raises die()
#
#  Edits the CONFFILE declarations in zero or more %file(s) by
#  * replacing CONFFILE=%DEFAULT_CONFFILE
#     with CONFFILE=%CONFFILE in shell files
#  * replacing %DEFAULT_CONFFILE with %CONFFILE in any other file
#
#  Does not edit files whose path relative to %TLP_ROOT is listed
#  in %CONFFILE_EDIT_BLACKLIST.
#  Additionally, does not edit symlinks.
#  Immediately returns $ERR_USAGE if %CONFFILE is not set or empty.
#
#  Dies on first failure.
#  Ignores inexistent files if TLP_CONFFILE_IGNORE_NOEXIST is set, else
#  calls die() (unless file is blacklisted).
#
tlp_set_conffile() {
   msg_debug "tlp_set_conffile ( $* )"
   [ -n "${CONFFILE:-}" ] || return ${ERR_USAGE}

   local _file
   for _file; do
      if is_protected_file "${_file}"; then
         true
      elif kw="${_file#${TLP_ROOT%/}/}" _in \
            ${SCRIPT_NAME:-} ${CONFFILE_EDIT_BLACKLIST:-}
      then
         msg_info "Not editing file '${_file}': blacklisted."

      elif [ -L "${_file}" ]; then
         true

      elif [ -f "${_file}" ]; then
         if is_shell_file "${_file}"; then
            # shell file
            msg_info "Editing CONFFILE in shell file '${_file}'"

            editvar_shell "CONFFILE" "${CONFFILE}" "${_file}" || \
               die "editvar_shell(file=${_file}) failed with code $?." $?
         else
            msg_info "Editing CONFFILE in generic file '${_file}'"

            ${X_SED} \
               -e "s=${DEFAULT_CONFFILE}=${CONFFILE}=g" -i "${_file}" || \
                  die "non-zero return ($?) for sed in file ${_file}." $?
         fi

      elif [ -z "${TLP_CONFFILE_IGNORE_NOEXIST:-}" ]; then
         die "file ${_file} does not exist."

      fi
   done
   return 0
}
# --- end of tlp_set_conffile (...) ---

# @true tlp_set_tpacpibat ( *file, **TLP_ROOT, **TPACPIBAT )
#
#  Edits the TPACPIBAT variable in %file if it is a shell file.
#
tlp_set_tpacpibat() {
   msg_debug "tlp_set_tpacpibat ( $* )"
   [ -n "${TPACPIBAT:-}" ] || return ${ERR_USAGE}

   local _file
   for _file; do
      if ! is_protected_file "${_file}" && \
         [ ! -L "${_file}" ] && \
         is_shell_file "${_file}" && \
         [ "x${_file#${TLP_ROOT%/}/}" != "x${SCRIPT_NAME:-}" ]
      then
         msg_info "Editing TPACPIBAT in shell file '${_file}'"

         editvar_shell "TPACPIBAT" "${TPACPIBAT}" "${_file}" || \
            die "editvar_shell(file=${_file}) failed with code $?." $?
      fi
   done
   return 0
}

# @true tlp_edit_files ( *func, **TLP_ROOT ), raises die()
#
#  Calls each function %func for each file in %TLP_ROOT.
#
#
tlp_edit_files() {
   msg_debug "tlp_edit_files ( $* )"
   : ${TLP_ROOT:?}

   local _file func

   local IFS="${_IFS_NEWLINE}"
   for _file in `${X_FIND} "${TLP_ROOT%/}/" -type f`; do
      IFS="${_IFS_DEFAULT}"

      for func; do
         ${func} "${_file}" || die "${func} (${_file}) returned $?."
      done

      # IFS=<newline> reassignment probably not required
      IFS="${_IFS_NEWLINE}"
   done

   IFS="${_IFS_DEFAULT}"
}
# --- end if tlp_edit_files (...) ---

# @true tlp_conffile ( [conffile], **TLP_ROOT, **CONFFILE ), raises die()
#
#  Executes tlp_set_conffile for each file in %TLP_ROOT.
#
tlp_conffile() {
   [ -z "${1:-}"        ] || CONFFILE="${1}"
   [ -n "${CONFFILE:-}" ] || print_usage "CONFFILE is not set."

   tlp_edit_files tlp_set_conffile
}
# --- end of tlp_conffile (...) ---

# @true tlp_tpacpibat ( [tpacpibat], **TLP_ROOT, **TPACPIBAT ), raises die()
#
# Executes tlp_set_tpacpibat for each file in %TLP_ROOT.
#
tlp_tpacpibat() {
   [ -z "${1:-}"         ] || TPACPIBAT="${1}"
   [ -n "${TPACPIBAT:-}" ] || print_usage "TPACPIBAT is not set."

   tlp_edit_files tlp_set_tpacpibat
}

# @noreturn print_usage ( [msg] ), raises exit(%ERR_USAGE)
#
#  Prints the given message (if any) to stderr,
#  followed by the general usage message (depening on %SCRIPT_MODE).
#  Exits afterwards with status %ERR_USAGE.
#
# arguments:
# * msg -- (specific) usage error message
#
print_usage() {
   [ -z "$*" ] || echo \!\!\!" $*" 1>&2
   case "${SCRIPT_MODE}" in
      configure)
echo "Usage: ${SCRIPT_NAME} [option [option...]]
where option is:
* --target <target>  -- configure target
* --from-env         -- same as '--target env'
* --src <dir>        -- root directory of TLP's source code (directory where
                        files will be edited)
                        Defaults to %TLP_ROOT if set, else %PWD will be used.
* --with-<option>,   -- enable/disable a (target-specific) option,
* --without-<option>    e.g. use the bundled tpacpi-bat file.
                        'with' has higher precedence than 'without'.
* --quiet, -q        -- be quiet
* --debug            -- be extra verbose (disables any previous --quiet switch)
* --help, -h         -- show this message

All options with a value can also be specified in --opt=<value> syntax.

Valid configure targets are:
* default, ubuntu -- do nothing
* gentoo          -- relocate TLP's config file to /etc/conf.d and use
                     an external tpacpi-bat script instead of the bundled one
* env             -- use variables (CONFFILE, TPACPIBAT) from the environment
                     and configure the source files accordingly
"
      ;;
      relocate_conffile)
echo "Usage: ${SCRIPT_NAME} [CONFFILE]
CONFFILE will be taken from env if not given as arg."
      ;;
      *)
         echo "Usage: unknown!"
   esac 1>&2
   exit ${ERR_USAGE}
}
# --- end of print_usage (...) ---

# int __configure__ ( *args )
#
#  Main function that configures TLP's source code. See print_usage() for
#  usage (or invoke this script as 'configure' with --help).
#
__configure__() {
   # do not guess the target OS: it's either specified (via --target=<...>)
   # or doesn't matter (i.e. use the default src == do nothing).

   local CONFIGURE_TARGET="default"

   local WITH= WITHOUT=

   local doshift opt value

   while [ $# -gt 0 ]; do
      doshift=1

      case "${1}" in
         --from-env)
            CONFIGURE_TARGET=env
         ;;
         --?*=*)
            # push back to %argv as '--opt' '<value>'
            opt="${1%%=*}"
            value="${1#--*=}"

            shift && doshift=0 && set -- "${opt}" "${value}" "$@" || \
               die "error while parsing args: --opt=<value> => --opt <value>"

            opt=
            value=
         ;;
         --target)
            doshift=2
            case "${2:-}" in
               '')
                  print_usage "Value for --target arg is missing or empty."
               ;;
               *)
                  CONFIGURE_TARGET="${2}"
               ;;
            esac
         ;;
         --src)
            doshift=2
            case "${2:-}" in
               '')
                  print_usage "Value for --src arg is missing or empty."
               ;;
               /*)
                  TLP_ROOT="${2%/}"
               ;;
               *)
                  TLP_ROOT="${PWD}/${2%/}"
               ;;
            esac
         ;;
         --quiet|-q)
            VERBOSE=
         ;;
         --with-*)
            WITH+=" ${1#--with-}"
         ;;
         --without-*)
            WITHOUT=" ${1#--without-}"
         ;;
         --debug)
            VERBOSE=y
            DEBUG=y
         ;;
         --)
            break
         ;;
         --help|-h)
            print_usage
         ;;
         *)
            print_usage "Unknown arg '${1}'."
         ;;
      esac

      if [ ${doshift} -gt 0 ]; then
         shift ${doshift} || \
            die "shift %doshift with non-zero return value."
      elif [ ${doshift} -eq 0 ]; then
         # legal case
         true
      else
         die "doshift < 0 while parsing args"
      fi
   done

   WITH="${WITH# }"
   WITHOUT="${WITHOUT# }"

   TLP_ROOT="${TLP_ROOT%/}"
   if [ ! -d "${TLP_ROOT}/" ]; then
      die "tlp src root directory '${TLP_ROOT}' does not exist."
   fi

   msg_debug "argv parsing mostly done."
   msg_debug " WITH='${WITH}' WITHOUT='${WITHOUT}' TLP_ROOT='${TLP_ROOT}' CONFIGURE_TARGET='${CONFIGURE_TARGET}'"

   case "${CONFIGURE_TARGET}" in
      default|ubuntu)
         msg_info "configure: nothing to do for target '${CONFIGURE_TARGET}'."
      ;;
      gentoo)
         tlp_conffile  "/etc/conf.d/tlp"
         if ! kw='tpacpi-bundled' _in ${WITH}; then
            tlp_tpacpibat "tpacpi-bat"
         fi
      ;;
      env)
         [ -z "${CONFFILE}"  ] || tlp_conffile
         [ -z "${TPACPIBAT}" ] || tlp_tpacpibat
      ;;
      *)
         print_usage "configure: unknown target '${CONFIGURE_TARGET}'."
      ;;
   esac
}
# --- end of __configure__ (...) ---

# int __main__ ( *args )
#
#  Multicall handler function that runs the actual main function depending
#  on %SCRIPT_NAME (and passes all args).
#
__main__() {
   case "${SCRIPT_NAME:?}" in
      tlp_configure*|configure*)
         SCRIPT_MODE=configure
         __configure__ "$@"
      ;;
      tlp_relocate_conffile*|relocate_conffile*)
      SCRIPT_MODE=relocate_conffile
         # __relocate_conffile__() {
         [ $# -lt 2 ] || print_usage "Too much args."
         case "${1:-}" in
            --help|-h)
               print_usage
            ;;
            *)
               tlp_conffile "${1:-}"
            ;;
         esac
         # }
      ;;
   esac
}
# --- end of __main__ (...) ---

## } // (TLP-)specific functions

SCRIPT_NAME="${0##*/}" __main__ "$@"
