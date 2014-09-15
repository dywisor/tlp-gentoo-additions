#!/bin/bash
#  a collection of commands/actions that edit TLP's sources
#
#  deps: bash, GNU find/xargs, grep, sed
#
# Usage: editsrc.bash [<option>...] [<command>...]
#
# Options:
#  -d, --src <dir>  -- path to TLP's sources (default: $PWD)
#  -h, --help       -- not implemented (script exits non-zero)
#
# Commands:
#
#  editcfgvar  VARNAME VALUE
#  cfgvar      VARNAME VALUE
#
#  cfg_append  LINE
#  @C          LINE
#
#  editvar     VARNAME VALUE
#  var         VARNAME VALUE
#
#  str_replace OLDVAL NEWVAL
#  replace     OLDVAL NEWVAL
#
#  editsrc     SED_EXPR
#
#  editmk      SED_EXPR
#  editmake    SED_EXPR
#
#  action      ACTION
#  macro       ACTION
#  x           ACTION
#
# Actions: see code below
#
# Notes:
# * Makefile-edit actions usually edit the install commands only
#
set -u

SRCFIND_RE_EXCLUDE=
SRCFIND_RE_EXCLUDE+="COPYING|LICENSE|changelog|Makefile|default|tpacpi-bat"
SRCFIND_RE_EXCLUDE+="|.*[.](rules|service|upstart|init|bash_comp.*)"
readonly SRCFIND_RE_EXCLUDE


die() {
   echo "${1:+died: }${1:-died.}" 1>&2
   exit ${2:-2}
}

autodie() {
   "$@" || die "command '$*' returned ${?}" ${?}
}

print_debug() {
   if [[ "${TLP_SRCEDIT_DEBUG:-n}" != "y" ]]; then
      true
   elif [[ $# -eq 0 ]]; then
      printf "\n" 1>&2
   elif [[ $# -gt 1 ]]; then
      local t="${1}"; shift
      printf "${t}\n" "$@" 1>&2
   else
      printf "%s\n" "${1}" 1>&2
   fi
}

# @stdout tlp_srcfind ( *dirs, **SRCFIND_RE_EXCLUDE )
tlp_srcfind() {
   find "$@" -maxdepth 1 -type f -print | \
      grep -vxE -- "([.]/)?(${SRCFIND_RE_EXCLUDE})"
   return ${PIPESTATUS[0]}
}

# tlp_src_get_editvar_expr (
#    varname, newval, qchar=\", expr_sepa:="@", **editvar_expr!
# )
#  creates a sed expr suitable for editing a variable defined on a single
#  line (no multiline defs!)
#
tlp_src_get_editvar_expr() {
   editvar_expr=
   [[ ( -n "${1-}" ) && ( -n "${2+SET}" ) ]] || die "bad usage"
   local match_expr q s

   # COULDFIX: also edits var="...' statements
   #            (but this should be a minor issue)
   #
   # regex groups:
   # 1: keyword    -- "readonly", "declare" or empty (whitespace preserved)
   # 2: varname    -- "varname="
   # 3: quote char -- ", ' or empty (discarded; " is used as quote char)
   # 4: old value  --
   # 5: quote char -- see 3
   # 6: remainder  -- only whitespace and end-of-line comments allowed
   #                  (will be discarded)
   #
   match_expr=
   match_expr+="^(\s*readonly\s+|\s*declare\s+|\s*)(${1}=)"
   match_expr+="([\'\"])?(.*?[^\'\"])?([\'\"])?(\s*|\s*#.+)\$"

   case "${2}" in
      *[^a-zA-Z0-9]*)
         q="${3-\"}"
      ;;
      *)
         q="${3-}"
      ;;
   esac

   s="${4:-@}"

   editvar_expr="s${s}${match_expr}${s}\1\2${q}${2}${q}${s}"
}

# tlp_src_apply_edit_expressions ( *file_list_cmdv, **edit_expressions )
tlp_src_apply_edit_expressions() {
   if [[ ${#edit_expressions[*]} -gt 0 ]]; then
      print_debug "%s: %s: %s" "find/edit" "${*}" "${edit_expressions[*]}"
      "$@" | xargs sed -i -r "${edit_expressions[@]}" -- || return ${?}
      return ${PIPESTATUS[0]}
   fi
}

# tlp_src_apply_edit_expressions_to ( *file, **edit_expressions )
tlp_src_apply_edit_expressions_to() {
   if [[ ${#edit_expressions[*]} -gt 0 ]]; then
      print_debug "%s: %s: %s" "edit" "${*}" "${edit_expressions[*]}"
      sed -i -r "${edit_expressions[@]}" -- "$@" || return ${?}
   fi
}

# tlp_src_zap_edit_expressions ( **edit_expressions! )
tlp_src_zap_edit_expressions() {
   edit_expressions=()
}

# tlp_src_add_edit_expressions ( *expr, **edit_expressions! )
#
tlp_src_add_edit_expressions() {
   while [[ $# -gt 0 ]]; do
      edit_expressions+=( -e "${1}" )
      shift
   done
}

# tlp_src_set_edit_expressions ( *expr, **edit_expressions! )
#
tlp_src_set_edit_expressions() {
   tlp_src_zap_edit_expressions
   tlp_src_add_edit_expressions "$@"
}


# expressions
# * that should be applied to most files in <src>/ and <src>/man/
editall_expressions=()
# * that should be applied to most files in <src>/
editvar_expressions=()
# * config file only
editcfg_expressions=()
# * makefile only
editmak_expressions=()

# additional actions
# * text that should be appended to the config file
cfgfile_append=()


while [[ $# -gt 0 ]]; do
   doshift=1
   arg="${1,,}"
   buf=; k=

   case "${arg}" in
      '-h'|'--help')
         die "no help available." 55
      ;;
      '-d'|'--src')
         doshift=2
         [[ $# -ge 2 ]] || die "${arg}: bad usage" 64
         cd "${2:?}" || die "chdir ${2} returned ${?}" ${?}
      ;;
      editcfgvar|cfgvar)
         doshift=3
         [[ $# -ge 3 ]] || die "${arg}: bad usage" 64
         tlp_src_get_editvar_expr "${2:?}" "${3?}"
         editcfg_expressions+=( "${editvar_expr}" )
      ;;
      cfg_append|@c)
         doshift=2
         [[ $# -ge 2 ]] || die "${arg}: bad usage" 64
         cfgfile_append+=( "${2}" )
      ;;
      editvar|var)
         doshift=3
         [[ $# -ge 3 ]] || die "${arg}: bad usage" 64
         tlp_src_get_editvar_expr "${2:?}" "${3?}"
         editvar_expressions+=( "${editvar_expr}" )
      ;;
      str_replace|replace)
         doshift=3
         [[ $# -ge 3 ]] || die "${arg}: bad usage" 64
         editall_expressions+=( "s@${2:?}@${3:?}@" )
      ;;
      editsrc)
         doshift=2
         [[ $# -ge 2 ]] || die "${arg}: bad usage" 64
         editall_expressions+=( "${2:?}" )
      ;;

      editmk|editmake)
         doshift=2
         [[ $# -ge 2 ]] || die "${arg}: bad usage" 64
         editmak_expressions+=( "${2:?}" )
      ;;
      action|macro|x)
         [[ $# -ge 2 ]] || die "${arg}: bad usage" 64
         buf="${2}"
         shift 2 || die
         doshift=0

         case "${buf}" in

            "conffile"|"CONFFILE")
               # ++ pass TLP_CONF to make
               #doshift=0
               [[ -n "${1-}" ]] || die "${arg}, ${buf}: arg expected."
               set -- str_replace /etc/default/tlp "$@"
            ;;
            "pcilist-sbin")
               editmak_expressions+=(
                  's@(install.*tlp-pcilist\s+)\$\(_BIN\)/@\1$(_SBIN)/@'
                  's@\(_BIN\)(/tlp-pcilist)@(_SBIN)\1@'
               )
            ;;
            "noinst")
               doshift=1
               [[ -n "${1-}" ]] || die "${arg}, ${buf}: arg expected."
               editmak_expressions+=( "/(install|ln)(\s.*)?\s+${1}/d" )
            ;;
            "no-radiosw")
               editmak_expressions+=( '/thinkpad-radiosw/d' )
            ;;

            # extra config options
            "TLP_LOAD_MODULES="*|"#TLP_LOAD_MODULES="*)
               cfgfile_append+=(
                  ""
                  "# disable automatic kernel module loading on startup"
                  "# n=disable, y=enable (default)"
                  "${buf}"
               )
            ;;
            "TLP_LOAD_MODULES")
               set -- X "#TLP_LOAD_MODULES=y" "$@"
            ;;
            "TLP_DEBUG")
               doshift=1
               [[ -n "${1+SET}" ]] || die "${arg}, ${buf}: arg expected."

               __tlp_debug_all="bat disk lock nm path pm rf run udev usb"

               cfgfile_append+=(
                  ""
                  "# select actions TLP should log about (syslog/journal)"
                  "# possible values: ${__tlp_debug_all}"
               )

               case "${1}" in
                  ''|'_')
                     cfgfile_append+=( "#TLP_DEBUG=\"\"" )
                  ;;
                  @all)
                     cfgfile_append+=( "TLP_DEBUG\"${__tlp_debug_all}\"" )
                  ;;
                  *)
                     cfgfile_append+=( "TLP_DEBUG=\"${1}\"" )
                  ;;
               esac
            ;;

            # TLPVER
            "setver")
               #doshift=0
               [[ -n "${1-}" ]] || die "${arg}, ${buf}: arg expected."
               set -- editvar TLPVER "$@"
            ;;
            "appendver")
               #doshift=0
               [[ -n "${1-}" ]] || die "${arg}, ${buf}: arg expected."
               k="\4${1:?}"
               shift || die
               set -- editvar TLPVER "${k}" "$@"
            ;;

            # buildroot macros
            #  *** should _not_ be used in full-featured distros ***
            "conffile-install-unconditional"|"conffile-inst")
               # = always overwrite the config file when installing
               editmak_expressions+=(
                  '/install.*default.*_CONF/s@^(\s*)\[.*?\]\s*\|\|@\1@'
               )
            ;;
            "no-pcilist"|"no-usblist")
               # = skip installation of tlp-{pci,usb}list
               k="${buf#no-}"; k="${k#tlp-}"
               editmak_expressions+=( "/tlp-${k}/d" )
            ;;
            "no-wireless")
               # = don't install tlp-rf
               # ! does not imply "no-radiosw"
               editmak_expressions+=( '/\(_BIN\)\/(bluetooth|wifi|wwan)/d' )
            ;;
            "libdir")
               # = relocate libdir files
               # * changes libdir ($LIBDIRS) from /usr/lib*/tlp-pm to $1
               # ! $1 should point to a TLP-specific dir
               #   (/usr/share/tlp-pm, but not /usr/share)
               # * changes TLP_TLIB in the Makefile
               # * tlp-functions already sets TPACPIBAT=$libdir/tpacpi-bat,
               #   nothing to do here
               # * special arg: share/sharedir: relocate to /usr/share/tlp-pm
               k=
               case "${1-}" in
                  '')
                     die "${arg}, ${buf}: arg expected."
                  ;;
                  /?*)
                     k="${1%/}"
                  ;;
                  share|sharedir)
                     k="/usr/share/tlp-pm"
                  ;;
                  *)
                     die "${arg}, ${buf}: relpath not allowed: ${1}"
                  ;;
               esac
               : ${k:?}
               shift || die

               tlp_src_get_editvar_expr LIBDIRS "${k}"
               editvar_expressions+=( "${editvar_expr}" )
               editmak_expressions+=(
                  "s@^(TLP_TLIB\s.*?=\s*).*/tlp-pm\s*\$@\1${k}@"
               )
            ;;

            *)
               die "${arg}: '${buf}' unknown" 64
            ;;
         esac
      ;;
      *)
         die "unknown arg: ${1}" 64
      ;;
   esac

   [[ ${doshift} -le 0 ]] || shift ${doshift:?}
done




#editall_expressions: ./man/
set +u
tlp_src_set_edit_expressions "${editall_expressions[@]}"
set -u
autodie tlp_src_apply_edit_expressions tlp_srcfind ./man/

#editvar_expressions + editall_expressions: ./
set +u
tlp_src_add_edit_expressions "${editvar_expressions[@]}"
set -u
autodie tlp_src_apply_edit_expressions tlp_srcfind ./

#editcfg_expressions: ./default
set +u
tlp_src_set_edit_expressions "${editcfg_expressions[@]}"
set -u
autodie tlp_src_apply_edit_expressions_to ./default

#editmak_expressions: ./Makefile
set +u
tlp_src_set_edit_expressions "${editmak_expressions[@]}"
set -u
autodie tlp_src_apply_edit_expressions_to ./Makefile

# append to config file
if [[ ${#cfgfile_append[*]} -gt 0 ]]; then
   {
      for line in \
         "# ------------------------------------------------------------------------------" \
         "# additional config options" \
         "" \
         "${cfgfile_append[@]}" \
         ""
      do
         printf "%s\n" "${line}"
      done
   } >> ./default || die "failed to write config file"
fi
