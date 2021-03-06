# -*- mode: shell-script -*-
# vim:ft=zsh

#
# Main state variables
#

typeset -gaH ZPLG_REGISTERED_PLUGINS ZPLG_TASKS ZPLG_RUN
ZPLG_TASKS=( "<no-data>" )
# Snippets loaded, url -> file name
typeset -gAH ZPLGM ZPLG_REGISTERED_STATES ZPLG_SNIPPETS ZPLG_REPORTS ZPLG_ICE ZPLG_SICE

#
# Common needed values
#

[[ ! -e "${ZPLGM[BIN_DIR]}"/zplugin.zsh ]] && ZPLGM[BIN_DIR]=""

ZPLGM[ZERO]="$0"
[[ ! -o "functionargzero" || "${ZPLGM[ZERO]/\//}" = "${ZPLGM[ZERO]}" ]] && ZPLGM[ZERO]="${(%):-%N}"

[[ -z "${ZPLGM[BIN_DIR]}" ]] && ZPLGM[BIN_DIR]="${ZPLGM[ZERO]:h}"

# Make ZPLGM[BIN_DIR] path absolute
if [[ "${ZPLGM[BIN_DIR]}" != /* ]]; then
    if [[ "${ZPLGM[BIN_DIR]}" = "." ]]; then
        ZPLGM[BIN_DIR]="$PWD"
    else
        ZPLGM[BIN_DIR]="$PWD/${ZPLGM[BIN_DIR]}"
    fi
fi

# Final test of ZPLGM[BIN_DIR]
if [[ ! -e "${ZPLGM[BIN_DIR]}"/zplugin.zsh ]]; then
    print "Could not establish ZPLGM[BIN_DIR] hash field. It should point where Zplugin's git repository is."
    return 1
fi

# User can override ZPLGM[HOME_DIR]
if [[ -z "${ZPLGM[HOME_DIR]}" ]]; then
    # Ignore ZDOTDIR if user manually put Zplugin to $HOME
    if [[ -d "$HOME/.zplugin" ]]; then
        ZPLGM[HOME_DIR]="$HOME/.zplugin"
    else
        ZPLGM[HOME_DIR]="${ZDOTDIR:-$HOME}/.zplugin"
    fi
fi

# Can be customized
: ${ZPLGM[PLUGINS_DIR]:=${ZPLGM[HOME_DIR]}/plugins}
: ${ZPLGM[COMPLETIONS_DIR]:=${ZPLGM[HOME_DIR]}/completions}
: ${ZPLGM[SNIPPETS_DIR]:=${ZPLGM[HOME_DIR]}/snippets}

builtin autoload -Uz is-at-least
is-at-least 5.1 && ZPLGM[NEW_AUTOLOAD]=1 || ZPLGM[NEW_AUTOLOAD]=0
#is-at-least 5.4 && ZPLGM[NEW_AUTOLOAD]=2

# Parameters - shadowing {{{
ZPLGM[SHADOWING]="inactive"
ZPLGM[DTRACE]="0"
typeset -gH ZPLG_CUR_PLUGIN=""
# }}}
# Parameters - function diffing {{{
typeset -gAH ZPLG_FUNCTIONS_BEFORE
typeset -gAH ZPLG_FUNCTIONS_AFTER
# Functions computed to be associated with plugin
typeset -gAH ZPLG_FUNCTIONS
#}}}
# Parameters - option diffing {{{
typeset -gAH ZPLG_OPTIONS_BEFORE
typeset -gAH ZPLG_OPTIONS_AFTER
# Concatenated options that changed, hold as they were before plugin load
typeset -gAH ZPLG_OPTIONS
# }}}
# Parameters - environment diffing {{{
typeset -gAH ZPLG_PATH_BEFORE
typeset -gAH ZPLG_PATH_AFTER
# Concatenated new elements of PATH (after diff)
typeset -gAH ZPLG_PATH
typeset -gAH ZPLG_FPATH_BEFORE
typeset -gAH ZPLG_FPATH_AFTER
# Concatenated new elements of FPATH (after diff)
typeset -gAH ZPLG_FPATH
# }}}
# Parameters - parameter diffing {{{
typeset -gAH ZPLG_PARAMETERS_BEFORE
typeset -gAH ZPLG_PARAMETERS_AFTER
# Concatenated *changed* previous elements of $parameters (before)
typeset -gAH ZPLG_PARAMETERS_PRE
# Concatenated *changed* current elements of $parameters (after)
typeset -gAH ZPLG_PARAMETERS_POST
# }}}
# Parameters - zstyle, bindkey, alias, zle remembering {{{
# Holds concatenated Zstyles declared by each plugin
# Concatenated after quoting, so (z)-splittable
typeset -gAH ZPLG_ZSTYLES

# Holds concatenated bindkeys declared by each plugin
typeset -gAH ZPLG_BINDKEYS

# Holds concatenated aliases declared by each plugin
typeset -gAH ZPLG_ALIASES

# Holds concatenated pairs "widget_name save_name" for use with zle -A
typeset -gAH ZPLG_WIDGETS_SAVED

# Holds concatenated names of widgets that should be deleted
typeset -gAH ZPLG_WIDGETS_DELETE

# Holds compdef calls (i.e. "${(j: :)${(q)@}}" of each call)
typeset -gaH ZPLG_COMPDEF_REPLAY
# }}}
# Parameters - ICE, swiss-knife {{{
declare -gA ZPLG_1MAP ZPLG_2MAP
ZPLG_1MAP=(
    "OMZ::" "https://github.com/robbyrussell/oh-my-zsh/trunk/"
    "PZT::" "https://github.com/sorin-ionescu/prezto/trunk/"
)
ZPLG_2MAP=(
    "OMZ::" "https://github.com/robbyrussell/oh-my-zsh/raw/master/"
    "PZT::" "https://github.com/sorin-ionescu/prezto/raw/master/"
)
# }}}

# Init {{{
zmodload zsh/zutil || return 1
zmodload zsh/parameter || return 1
zmodload zsh/terminfo 2>/dev/null
zmodload zsh/termcap 2>/dev/null

[[ ( "${+terminfo}" = 1 && -n "${terminfo[colors]}" ) || ( "${+termcap}" = 1 && -n "${termcap[Co]}" ) ]] && {
    ZPLGM+=(
        "col-title"     ""
        "col-pname"     $'\e[33m'
        "col-uname"     $'\e[35m'
        "col-keyword"   $'\e[32m'
        "col-error"     $'\e[31m'
        "col-p"         $'\e[01m\e[34m'
        "col-bar"       $'\e[01m\e[35m'
        "col-info"      $'\e[32m'
        "col-info2"     $'\e[32m'
        "col-uninst"    $'\e[01m\e[34m'
        "col-success"   $'\e[01m\e[32m'
        "col-failure"   $'\e[31m'
        "col-rst"       $'\e[0m'
    )
}

# List of hooks
typeset -gAH ZPLG_ZLE_HOOKS_LIST
ZPLG_ZLE_HOOKS_LIST=(
    zle-line-init "1"
    zle-line-finish "1"
    paste-insert "1"
    zle-isearch-exit "1"
    zle-isearch-update "1"
    zle-history-line-set "1"
    zle-keymap-select "1"
)

builtin setopt noaliases

# }}}

#
# Shadowing-related functions
#

# FUNCTION: --zplg-reload-and-run {{{
# Marks given function ($3) for autoloading, and executes it triggering the
# load. $1 is the fpath dedicated to the function, $2 are autoload options.
# This function replaces "autoload -X", because using that on older Zsh
# versions causes problems with traps.
#
# So basically one creates function stub that calls --zplg-reload-and-run()
# instead of "autoload -X".
#
# $1 - FPATH dedicated to function
# $2 - autoload options
# $3 - function name (one that needs autoloading)
#
# Author: Bart Schaefer
--zplg-reload-and-run () {
    local fpath_prefix="$1" autoload_opts="$2" func="$3"
    shift 3

    # Unfunction caller function (its name is given)
    unfunction -- "$func"

    local FPATH="$fpath_prefix":"${FPATH}"

    # After this the function exists again
    local IFS=" "
    builtin autoload $=autoload_opts -- "$func"

    # User wanted to call the function, not only load it
    "$func" "$@"
} # }}}
# FUNCTION: --zplg-shadow-autoload {{{
# Function defined to hijack plugin's calls to `autoload' builtin.
#
# The hijacking is not only to gather report data, but also to
# run custom `autoload' function, that doesn't need FPATH.
--zplg-shadow-autoload () {
    local -a opts
    local func

    # TODO: +X
    zparseopts -a opts -D ${(s::):-TUXkmtzw}

    if (( ${+opts[(r)-X]} )); then
        -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Warning: Failed autoload $opts $*"
        print -u2 "builtin autoload required for $opts"
        return 1
    fi
    if (( ${+opts[(r)-w]} )); then
        -zplg-add-report "${ZPLGM[CUR_USPL2]}" "-w-Autoload $opts $*"
        builtin autoload $opts "$@"
        return 0
    fi

    # Report ZPLUGIN's "native" autoloads
    for func; do
        -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Autoload $func${opts:+ with options ${opts[*]}}"
    done

    # Do ZPLUGIN's "native" autoloads
    if [[ "$ZPLGM[CUR_USR]" = "%" ]] && local PLUGIN_DIR="$ZPLG_CUR_PLUGIN" || local PLUGIN_DIR="${ZPLGM[PLUGINS_DIR]}/${ZPLGM[CUR_USR]}---${ZPLG_CUR_PLUGIN}"
    for func; do
        # Real autoload doesn't touch function if it already exists
        # Author of the idea of FPATH-clean autoloading: Bart Schaefer
        if (( ${+functions[$func]} != 1 )); then
            builtin setopt noaliases
            if [[ "${ZPLGM[NEW_AUTOLOAD]}" = "2" ]]; then
                builtin autoload ${opts[@]} "$PLUGIN_DIR/$func"
            elif [[ "${ZPLGM[NEW_AUTOLOAD]}" = "1" ]]; then
                eval "function ${(q)func} {
                    local FPATH=${(qqq)PLUGIN_DIR}:${(qqq)FPATH}
                    builtin autoload -X ${(q-)opts[@]}
                }"
            else
                eval "function ${(q)func} {
                    --zplg-reload-and-run ${(q)PLUGIN_DIR} ${(qq)opts[*]} ${(q)func} "'"$@"
                }'
            fi
            builtin unsetopt noaliases
        fi
    done

    return 0
} # }}}
# FUNCTION: --zplg-shadow-bindkey {{{
# Function defined to hijack plugin's calls to `bindkey' builtin.
#
# The hijacking is to gather report data (which is used in unload).
--zplg-shadow-bindkey() {
    -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Bindkey $*"

    # Remember to perform the actual bindkey call
    typeset -a pos
    pos=( "$@" )

    # Check if we have regular bindkey call, i.e.
    # with no options or with -s, plus possible -M
    # option
    local -A optsA
    zparseopts -A optsA -D ${(s::):-lLdDAmrsevaR} "M:" "N:"

    local -a opts
    opts=( "${(k)optsA[@]}" )

    if [[ "${#opts[@]}" -eq "0" ||
        ( "${#opts[@]}" -eq "1" && "${+opts[(r)-M]}" = "1" ) ||
        ( "${#opts[@]}" -eq "1" && "${+opts[(r)-R]}" = "1" ) ||
        ( "${#opts[@]}" -eq "1" && "${+opts[(r)-s]}" = "1" ) ||
        ( "${#opts[@]}" -le "2" && "${+opts[(r)-M]}" = "1" && "${+opts[(r)-s]}" = "1" ) ||
        ( "${#opts[@]}" -le "2" && "${+opts[(r)-M]}" = "1" && "${+opts[(r)-R]}" = "1" )
    ]]; then
        local string="${(q)1}" widget="${(q)2}"
        local quoted

        # "-M map" given?
        if (( ${+opts[(r)-M]} )); then
            local Mopt="-M"
            local Marg="${optsA[-M]}"

            Mopt="${(q)Mopt}"
            Marg="${(q)Marg}"

            quoted="$string $widget $Mopt $Marg"
        else
            quoted="$string $widget"
        fi

        # -R given?
        if (( ${+opts[(r)-R]} )); then
            local Ropt="-R"
            Ropt="${(q)Ropt}"

            if (( ${+opts[(r)-M]} )); then
                quoted="$quoted $Ropt"
            else
                # Two empty fields for non-existent -M arg
                local space="_"
                space="${(q)space}"
                quoted="$quoted $space $space $Ropt"
            fi
        fi

        quoted="${(q)quoted}"

        # Remember the bindkey, only when load is in progress (it can be dstart that leads execution here)
        [[ -n "${ZPLGM[CUR_USPL2]}" ]] && ZPLG_BINDKEYS[${ZPLGM[CUR_USPL2]}]+="$quoted "
        # Remember for dtrace
        [[ "${ZPLGM[DTRACE]}" = "1" ]] && ZPLG_BINDKEYS[_dtrace/_dtrace]+="$quoted "
    else
        # bindkey -A newkeymap main?
        # Negative indices for KSH_ARRAYS immunity
        if [[ "${#opts[@]}" -eq "1" && "${+opts[(r)-A]}" = "1" && "${#pos[@]}" = "3" && "${pos[-1]}" = "main" && "${pos[-2]}" != "-A" ]]; then
            # Save a copy of main keymap
            (( ZPLGM[BINDKEY_MAIN_IDX] = ${ZPLGM[BINDKEY_MAIN_IDX]:-0} + 1 ))
            local pname="${ZPLG_CUR_PLUGIN:-_dtrace}"
            local name="${(q)pname}-main-${ZPLGM[BINDKEY_MAIN_IDX]}"
            builtin bindkey -N "$name" main

            # Remember occurence of main keymap substitution, to revert on unload
            local keys="_" widget="_" optA="-A" mapname="${name}" optR="_"
            local quoted="${(q)keys} ${(q)widget} ${(q)optA} ${(q)mapname} ${(q)optR}"
            quoted="${(q)quoted}"

            # Remember the bindkey, only when load is in progress (it can be dstart that leads execution here)
            [[ -n "${ZPLGM[CUR_USPL2]}" ]] && ZPLG_BINDKEYS[${ZPLGM[CUR_USPL2]}]+="$quoted "
            [[ "${ZPLGM[DTRACE]}" = "1" ]] && ZPLG_BINDKEYS[_dtrace/_dtrace]+="$quoted "

            -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Warning: keymap \`main' copied to \`${name}' because of \`${pos[-2]}' substitution"
        # bindkey -N newkeymap [other]
        elif [[ "${#opts[@]}" -eq 1 && "${+opts[(r)-N]}" = "1" ]]; then
            local Nopt="-N"
            local Narg="${optsA[-N]}"

            local keys="_" widget="_" optN="-N" mapname="${Narg}" optR="_"
            local quoted="${(q)keys} ${(q)widget} ${(q)optN} ${(q)mapname} ${(q)optR}"
            quoted="${(q)quoted}"

            # Remember the bindkey, only when load is in progress (it can be dstart that leads execution here)
            [[ -n "${ZPLGM[CUR_USPL2]}" ]] && ZPLG_BINDKEYS[${ZPLGM[CUR_USPL2]}]+="$quoted "
            [[ "${ZPLGM[DTRACE]}" = "1" ]] && ZPLG_BINDKEYS[_dtrace/_dtrace]+="$quoted "
        else
            -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Warning: last bindkey used non-typical options: ${opts[*]}"
        fi
    fi

    # A. Shadow off. Unfunction bindkey
    # 0.autoload, A.bindkey, B.zstyle, C.alias, D.zle, E.compdef
    (( ${+ZPLGM[bkp-bindkey]} )) && functions[bindkey]="${ZPLGM[bkp-bindkey]}" || unfunction "bindkey"

    # Actual bindkey
    bindkey "${pos[@]}"
    integer ret=$?

    # A. Shadow on. Custom function could unfunction itself
    (( ${+functions[bindkey]} )) && ZPLGM[bkp-bindkey]="${functions[bindkey]}" || unset "ZPLGM[bkp-bindkey]"
    functions[bindkey]='--zplg-shadow-bindkey "$@";'

    return $ret # testable
} # }}}
# FUNCTION: --zplg-shadow-zstyle {{{
# Function defined to hijack plugin's calls to `zstyle' builtin.
#
# The hijacking is to gather report data (which is used in unload).
--zplg-shadow-zstyle() {
    -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Zstyle $*"

    # Remember to perform the actual zstyle call
    typeset -a pos
    pos=( "$@" )

    # Check if we have regular zstyle call, i.e.
    # with no options or with -e
    local -a opts
    zparseopts -a opts -D ${(s::):-eLdgabsTtm}

    if [[ "${#opts[@]}" -eq 0 || ( "${#opts[@]}" -eq 1 && "${+opts[(r)-e]}" = "1" ) ]]; then
        # Have to quote $1, then $2, then concatenate them, then quote them again
        local pattern="${(q)1}" style="${(q)2}"
        local ps="$pattern $style"
        ps="${(q)ps}"

        # Remember the zstyle, only when load is in progress (it can be dstart that leads execution here)
        [[ -n "${ZPLGM[CUR_USPL2]}" ]] && ZPLG_ZSTYLES[${ZPLGM[CUR_USPL2]}]+="$ps "
        # Remember for dtrace
        [[ "${ZPLGM[DTRACE]}" = "1" ]] && ZPLG_ZSTYLES[_dtrace/_dtrace]+="$ps "
    else
        if [[ ! "${#opts[@]}" = "1" && ( "${+opts[(r)-s]}" = "1" || "${+opts[(r)-b]}" = "1" || "${+opts[(r)-a]}" = "1" ||
                                      "${+opts[(r)-t]}" = "1" || "${+opts[(r)-T]}" = "1" || "${+opts[(r)-m]}" = "1" ) ]]
        then
            -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Warning: last zstyle used non-typical options: ${opts[*]}"
        fi
    fi

    # B. Shadow off. Unfunction zstyle
    # 0.autoload, A.bindkey, B.zstyle, C.alias, D.zle, E.compdef
    (( ${+ZPLGM[bkp-zstyle]} )) && functions[zstyle]="${ZPLGM[bkp-zstyle]}" || unfunction "zstyle"

    # Actual zstyle
    zstyle "${pos[@]}"
    integer ret=$?

    # B. Shadow on. Custom function could unfunction itself
    (( ${+functions[zstyle]} )) && ZPLGM[bkp-zstyle]="${functions[zstyle]}" || unset "ZPLGM[bkp-zstyle]"
    functions[zstyle]='--zplg-shadow-zstyle "$@";'

    return $ret # testable
} # }}}
# FUNCTION: --zplg-shadow-alias {{{
# Function defined to hijack plugin's calls to `alias' builtin.
#
# The hijacking is to gather report data (which is used in unload).
--zplg-shadow-alias() {
    -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Alias $*"

    # Remember to perform the actual alias call
    typeset -a pos
    pos=( "$@" )

    local -a opts
    zparseopts -a opts -D ${(s::):-gs}

    local a quoted tmp
    for a in "$@"; do
        local aname="${a%%[=]*}"
        local avalue="${a#*=}"

        # Check if alias is to be redefined
        (( ${+aliases[$aname]} )) && -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Warning: redefining alias \`${aname}', previous value: ${aliases[$aname]}"

        local bname=${(q)aliases[$aname]}
        aname="${(q)aname}"

        if (( ${+opts[(r)-s]} )); then
            tmp="-s"
            tmp="${(q)tmp}"
            quoted="$aname $bname $tmp"
        elif (( ${+opts[(r)-g]} )); then
            tmp="-g"
            tmp="${(q)tmp}"
            quoted="$aname $bname $tmp"
        else
            quoted="$aname $bname"
        fi

        quoted="${(q)quoted}"

        # Remember the alias, only when load is in progress (it can be dstart that leads execution here)
        [[ -n "${ZPLGM[CUR_USPL2]}" ]] && ZPLG_ALIASES[${ZPLGM[CUR_USPL2]}]+="$quoted "
        # Remember for dtrace
        [[ "${ZPLGM[DTRACE]}" = "1" ]] && ZPLG_ALIASES[_dtrace/_dtrace]+="$quoted "
    done

    # C. Shadow off. Unfunction alias
    # 0.autoload, A.bindkey, B.zstyle, C.alias, D.zle, E.compdef
    (( ${+ZPLGM[bkp-alias]} )) && functions[alias]="${ZPLGM[bkp-alias]}" || unfunction "alias"

    # Actual alias
    alias "${pos[@]}"
    integer ret=$?

    # C. Shadow on. Custom function could unfunction itself
    (( ${+functions[alias]} )) && ZPLGM[bkp-alias]="${functions[alias]}" || unset "ZPLGM[bkp-alias]"
    functions[alias]='--zplg-shadow-alias "$@";'

    return $ret # testable
} # }}}
# FUNCTION: --zplg-shadow-zle {{{
# Function defined to hijack plugin's calls to `zle' builtin.
#
# The hijacking is to gather report data (which is used in unload).
--zplg-shadow-zle() {
    -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Zle $*"

    # Remember to perform the actual zle call
    typeset -a pos
    pos=( "$@" )

    set -- "${@:#--}"

    # Try to catch game-changing "-N"
    if [[ "$1" = "-N" && "$#" = "3" ]]; then
            # Hooks
            if [[ "${ZPLG_ZLE_HOOKS_LIST[$2]}" = "1" ]]; then
                local quoted="$2"
                quoted="${(q)quoted}"
                # Remember only when load is in progress (it can be dstart that leads execution here)
                [[ -n "${ZPLGM[CUR_USPL2]}" ]] && ZPLG_WIDGETS_DELETE[${ZPLGM[CUR_USPL2]}]+="$quoted "
            # These will be saved and restored
            elif (( ${+widgets[$2]} )); then
                # Have to remember original widget "$2" and
                # the copy that it's going to be done
                local widname="$2" saved_widname="zplugin-saved-$2"
                builtin zle -A "$widname" "$saved_widname"

                widname="${(q)widname}"
                saved_widname="${(q)saved_widname}"
                local quoted="$widname $saved_widname"
                quoted="${(q)quoted}"
                # Remember only when load is in progress (it can be dstart that leads execution here)
                [[ -n "${ZPLGM[CUR_USPL2]}" ]] && ZPLG_WIDGETS_SAVED[${ZPLGM[CUR_USPL2]}]+="$quoted "
                # Remember for dtrace
                [[ "${ZPLGM[DTRACE]}" = "1" ]] && ZPLG_WIDGETS_SAVED[_dtrace/_dtrace]+="$quoted "
             # These will be deleted
             else
                 -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Warning: unknown widget replaced/taken via zle -N: \`$2', it is set to be deleted"
                 local quoted="$2"
                 quoted="${(q)quoted}"
                 # Remember only when load is in progress (it can be dstart that leads execution here)
                 [[ -n "${ZPLGM[CUR_USPL2]}" ]] && ZPLG_WIDGETS_DELETE[${ZPLGM[CUR_USPL2]}]+="$quoted "
                 # Remember for dtrace
                 [[ "${ZPLGM[DTRACE]}" = "1" ]] && ZPLG_WIDGETS_DELETE[_dtrace/_dtrace]+="$quoted "
             fi
    # Creation of new widgets. They will be removed on unload
    elif [[ "$1" = "-N" && "$#" = "2" ]]; then
        local quoted="$2"
        quoted="${(q)quoted}"
        # Remember only when load is in progress (it can be dstart that leads execution here)
        [[ -n "${ZPLGM[CUR_USPL2]}" ]] && ZPLG_WIDGETS_DELETE[${ZPLGM[CUR_USPL2]}]+="$quoted "
        # Remember for dtrace
        [[ "${ZPLGM[DTRACE]}" = "1" ]] && ZPLG_WIDGETS_DELETE[_dtrace/_dtrace]+="$quoted "
    fi

    # D. Shadow off. Unfunction zle
    # 0.autoload, A.bindkey, B.zstyle, C.alias, D.zle, E.compdef
    (( ${+ZPLGM[bkp-zle]} )) && functions[zle]="${ZPLGM[bkp-zle]}" || unfunction "zle"

    # Actual zle
    zle "${pos[@]}"
    integer ret=$?

    # D. Shadow on. Custom function could unfunction itself
    (( ${+functions[zle]} )) && ZPLGM[bkp-zle]="${functions[zle]}" || unset "ZPLGM[bkp-zle]"
    functions[zle]='--zplg-shadow-zle "$@";'

    return $ret # testable
} # }}}
# FUNCTION: --zplg-shadow-compdef {{{
# Function defined to hijack plugin's calls to `compdef' function.
# The hijacking is not only for reporting, but also to save compdef
# calls so that `compinit' can be called after loading plugins.
--zplg-shadow-compdef() {
    -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Saving \`compdef $*' for replay"
    ZPLG_COMPDEF_REPLAY+=( "${(j: :)${(q)@}}" )

    return 0 # testable
} # }}}
# FUNCTION: -zplg-shadow-on {{{
# Turn on shadowing of builtins and functions according to passed
# mode ("load", "light" or "compdef"). The shadowing is to gather
# report data, and to hijack `autoload' and `compdef' calls.
-zplg-shadow-on() {
    local mode="$1"

    # Enable shadowing only once
    #
    # One could expect possibility of widening of shadowing, however
    # such sequence doesn't exist, e.g. "light" then "load"/"dtrace",
    # "compdef" then "load"/"dtrace", "light" then "compdef",
    # "compdef" then "light"
    #
    # It is always "dtrace" then "load" (i.e. dtrace then load)
    # "dtrace" then "light" (i.e. dtrace then light load)
    # "dtrace" then "compdef" (i.e. dtrace then snippet)
    [[ "${ZPLGM[SHADOWING]}" != "inactive" ]] && builtin return 0

    ZPLGM[SHADOWING]="$mode"

    # The point about backuping is: does the key exist in functions array
    # If it does exist, then it will also exist as ZPLGM[bkp-*]

    # Defensive code, shouldn't be needed
    builtin unset "ZPLGM[bkp-autoload]" "ZPLGM[bkp-compdef]"  # 0, E.

    if [[ "$mode" != "compdef" ]]; then
        # 0. Used, but not in temporary restoration, which doesn't happen for autoload
        (( ${+functions[autoload]} )) && ZPLGM[bkp-autoload]="${functions[autoload]}"
        functions[autoload]='--zplg-shadow-autoload "$@";'
    fi

    # E. Always shadow compdef
    (( ${+functions[compdef]} )) && ZPLGM[bkp-compdef]="${functions[compdef]}"
    functions[compdef]='--zplg-shadow-compdef "$@";'

    # Light and compdef shadowing stops here. Dtrace and load go on
    [[ "$mode" = "light" || "$mode" = "compdef" ]] && return 0

    # Defensive code, shouldn't be needed. A, B, C, D
    builtin unset "ZPLGM[bkp-bindkey]" "ZPLGM[bkp-zstyle]" "ZPLGM[bkp-alias]" "ZPLGM[bkp-zle]"

    # A.
    (( ${+functions[bindkey]} )) && ZPLGM[bkp-bindkey]="${functions[bindkey]}"
    functions[bindkey]='--zplg-shadow-bindkey "$@";'

    # B.
    (( ${+functions[zstyle]} )) && ZPLGM[bkp-zstyle]="${functions[zstyle]}"
    functions[zstyle]='--zplg-shadow-zstyle "$@";'

    # C.
    (( ${+functions[alias]} )) && ZPLGM[bkp-alias]="${functions[alias]}"
    functions[alias]='--zplg-shadow-alias "$@";'

    # D.
    (( ${+functions[zle]} )) && ZPLGM[bkp-zle]="${functions[zle]}"
    functions[zle]='--zplg-shadow-zle "$@";'

    builtin return 0
} # }}}
# FUNCTION: -zplg-shadow-off {{{
# Turn off shadowing completely for a given mode ("load", "light"
# or "compdef").
-zplg-shadow-off() {
    builtin setopt localoptions noaliases
    local mode="$1"

    # Disable shadowing only once
    # Disable shadowing only the way it was enabled first
    [[ "${ZPLGM[SHADOWING]}" = "inactive" || "${ZPLGM[SHADOWING]}" != "$mode" ]] && return 0

    ZPLGM[SHADOWING]="inactive"

    if [[ "$mode" != "compdef" ]]; then
    # 0. Unfunction "autoload"
    (( ${+ZPLGM[bkp-autoload]} )) && functions[autoload]="${ZPLGM[bkp-autoload]}" || unfunction "autoload"
    fi

    # E. Restore original compdef if it existed
    (( ${+ZPLGM[bkp-compdef]} )) && functions[compdef]="${ZPLGM[bkp-compdef]}" || unfunction "compdef"

    # Light and comdef shadowing stops here
    [[ "$mode" = "light" || "$mode" = "compdef" ]] && return 0

    # Unfunction shadowing functions

    # A.
    (( ${+ZPLGM[bkp-bindkey]} )) && functions[bindkey]="${ZPLGM[bkp-bindkey]}" || unfunction "bindkey"
    # B.
    (( ${+ZPLGM[bkp-zstyle]} )) && functions[zstyle]="${ZPLGM[bkp-zstyle]}" || unfunction "zstyle"
    # C.
    (( ${+ZPLGM[bkp-alias]} )) && functions[alias]="${ZPLGM[bkp-alias]}" || unfunction "alias"
    # D.
    (( ${+ZPLGM[bkp-zle]} )) && functions[zle]="${ZPLGM[bkp-zle]}" || unfunction "zle"

    return 0
} # }}}
# FUNCTION: pmodload {{{
# Compatibility with Prezto. Calls can be recursive.
(( ${+functions[pmodload]} )) || pmodload() {
    while (( $# )); do
        [[ -z "${ZPLG_SNIPPETS[PZT::modules/$1${ZPLG_ICE[svn]-/init.zsh}]}" ]] && -zplg-load-snippet PZT::modules/"$1${ZPLG_ICE[svn]-/init.zsh}"
        shift
    done
}
# }}}

#
# Diff functions
#

# FUNCTION: -zplg-diff-functions {{{
# Implements detection of newly created functions. Performs
# data gathering, computation is done in *-compute().
#
# $1 - user/plugin (i.e. uspl2 format)
# $2 - command, can be "begin" or "end"
-zplg-diff-functions() {
    local uspl2="$1"
    local cmd="$2"

    ZPLG_FUNCTIONS[$uspl2]=""
    [[ "$cmd" = "begin" ]] && ZPLG_FUNCTIONS_BEFORE[$uspl2]="${(j: :)${(qk)functions[@]}}" || ZPLG_FUNCTIONS_AFTER[$uspl2]="${(j: :)${(qk)functions[@]}}"
} # }}}
# FUNCTION: -zplg-diff-options {{{
# Implements detection of change in option state. Performs
# data gathering, computation is done in *-compute().
#
# $1 - user/plugin (i.e. uspl2 format)
# $2 - command, can be "begin" or "end"
-zplg-diff-options() {
    local IFS=" "

    [[ "$2" = "begin" ]] && ZPLG_OPTIONS_BEFORE[$1]="${(kv)options[@]}" || ZPLG_OPTIONS_AFTER[$1]="${(kv)options[@]}"

    ZPLG_OPTIONS[$1]=""
} # }}}
# FUNCTION: -zplg-diff-env {{{
# Implements detection of change in PATH and FPATH.
#
# $1 - user/plugin (i.e. uspl2 format)
# $2 - command, can be "begin" or "end"
-zplg-diff-env() {
    typeset -a tmp
    local IFS=" "

    [[ "$2" = "begin" ]] && {
            tmp=( "${(q)path[@]}" )
            ZPLG_PATH_BEFORE[$1]="${tmp[*]}"
            tmp=( "${(q)fpath[@]}" )
            ZPLG_FPATH_BEFORE[$1]="${tmp[*]}"
    } || {
            tmp=( "${(q)path[@]}" )
            ZPLG_PATH_AFTER[$1]="${tmp[*]}"
            tmp=( "${(q)fpath[@]}" )
            ZPLG_FPATH_AFTER[$1]="${tmp[*]}"
    }

    ZPLG_PATH[$1]=""
    ZPLG_FPATH[$1]=""
} # }}}
# FUNCTION: -zplg-diff-parameter {{{
# Implements detection of change in any parameter's existence and type.
# Performs data gathering, computation is done in *-compute().
#
# $1 - user/plugin (i.e. uspl2 format)
# $2 - command, can be "begin" or "end"
-zplg-diff-parameter() {
    typeset -a tmp

    [[ "$2" = "begin" ]] && ZPLG_PARAMETERS_BEFORE[$1]="${(j: :)${(qkv)parameters[@]}}" || ZPLG_PARAMETERS_AFTER[$1]="${(j: :)${(qkv)parameters[@]}}"

    ZPLG_PARAMETERS_PRE[$1]=""
    ZPLG_PARAMETERS_POST[$1]=""
} # }}}

#
# Utility functions
#

# FUNCTION: -zplg-any-to-user-plugin {{{
# Allows elastic plugin-spec across the code.
#
# $1 - plugin spec (4 formats: user---plugin, user/plugin, user, plugin)
# $2 - plugin (only when $1 - i.e. user - given)
#
# Returns user and plugin in $reply
#
-zplg-any-to-user-plugin() {
    # Two components given?
    # That's a pretty fast track to call this function this way
    if [[ -n "$2" ]];then
        # But user name is empty?
        [[ -z "$1" ]] && 1="_local"

        reply=( "$1" "$2" )
        return 0
    fi

    # Is it absolute path?
    if [[ "${1[1]}" = "/" ]]; then
        reply=( "%" "$1" )
        return 0
    fi

    # Is it absolute path in zplugin format?
    if [[ "${1[1]}" = "%" ]]; then
        reply=( "%" "${${${1/\%HOME/$HOME}/\%SNIPPETS/${ZPLGM[SNIPPETS_DIR]}}#%}" )
        [[ "${${reply[2]}[1]}" != "/" ]] && reply[2]="/${reply[2]}"
        return 0
    fi

    # Rest is for single component given
    # It doesn't touch $2

    local user="${1%%/*}" plugin="${1#*/}"
    if [[ "$user" = "$plugin" ]]; then
        # Is it really the same plugin and user name?
        if [[ "$user/$plugin" = "$1" ]]; then
            reply=( "$user" "$plugin" )
            return 0
        fi

        user="${1%%---*}"
        plugin="${1#*---}"
    fi

    if [[ "$user" = "$plugin" ]]; then
        # Is it really the same plugin and user name?
        if [[ "${user}---${plugin}" = "$1" ]]; then
            reply=( "$user" "$plugin" )
            return 0
        fi
        user="_local"
    fi

    if [[ -z "$user" ]]; then
        user="_local"
    fi

    if [[ -z "$plugin" ]]; then
        plugin="_unknown"
    fi

    reply=( "$user" "$plugin" )
    return 0
} # }}}
# FUNCTION: -zplg-find-other-matches {{{
# Plugin's main source file is in general `name.plugin.zsh'. However,
# there can be different conventions, if that file is not found, then
# this functions examines other conventions in order of most expected
# sanity.
-zplg-find-other-matches() {
    local pdir_path="$1" pbase="$2"

    if [[ -e "$pdir_path/init.zsh" ]]; then
        reply=( "$pdir_path/init.zsh" )
    elif [[ -e "$pdir_path/${pbase}.zsh-theme" ]]; then
        reply=( "$pdir_path/${pbase}.zsh-theme" )
    elif [[ -e "$pdir_path/${pbase}.theme.zsh" ]]; then
        reply=( "$pdir_path/${pbase}.theme.zsh" )
    else
        reply=(
            $pdir_path/*.plugin.zsh(N) $pdir_path/*.zsh-theme(N)
            $pdir_path/*.zsh(N) $pdir_path/*.sh(N) $pdir_path/.zshrc(N)
        )
    fi
} # }}}
# FUNCTION: -zplg-register-plugin {{{
-zplg-register-plugin() {
    local uspl2="$1" mode="$2"
    integer ret=0

    if [[ -z "${ZPLG_REGISTERED_PLUGINS[(r)$uspl2]}" ]]; then
        ZPLG_REGISTERED_PLUGINS+=( "$uspl2" )
    else
        # Allow overwrite-load, however warn about it
        [[ -z "${ZPLGM[TEST]}" ]] && print "Warning: plugin \`$uspl2' already registered, will overwrite-load"
        ret=1
    fi

    # Full or light load?
    [[ "$mode" = "light" ]] && ZPLG_REGISTERED_STATES[$uspl2]="1" || ZPLG_REGISTERED_STATES[$uspl2]="2"

    ZPLG_REPORTS[$uspl2]=""
    # Functions
    ZPLG_FUNCTIONS_BEFORE[$uspl2]="" ZPLG_FUNCTIONS_AFTER[$uspl2]="" ZPLG_FUNCTIONS[$uspl2]=""
    # Objects
    ZPLG_ZSTYLES[$uspl2]=""          ZPLG_BINDKEYS[$uspl2]=""        ZPLG_ALIASES[$uspl2]=""
    # Widgets
    ZPLG_WIDGETS_SAVED[$uspl2]=""    ZPLG_WIDGETS_DELETE[$uspl2]=""
    # Rest (options and (f)path)
    ZPLG_OPTIONS[$uspl2]=""          ZPLG_PATH[$uspl2]=""            ZPLG_FPATH[$uspl2]=""

    return $ret
} # }}}
# FUNCTION: -zplg-unregister-plugin {{{
-zplg-unregister-plugin() {
    -zplg-any-to-user-plugin "$1" "$2"
    local uspl2="${reply[-2]}/${reply[-1]}"

    # If not found, the index will be length+1
    ZPLG_REGISTERED_PLUGINS[${ZPLG_REGISTERED_PLUGINS[(i)$uspl2]}]=()
    ZPLG_REGISTERED_STATES[$uspl2]="0"
} # }}}

#
# Remaining functions
#

# FUNCTION: -zplg-prepare-home {{{
# Creates all directories needed by Zplugin, first checks
# if they already exist.
-zplg-prepare-home() {
    [[ -n "${ZPLGM[HOME_READY]}" ]] && return
    ZPLGM[HOME_READY]="1"

    [[ ! -d "${ZPLGM[HOME_DIR]}" ]] && {
        command mkdir 2>/dev/null "${ZPLGM[HOME_DIR]}"
        # For compaudit
        command chmod go-w "${ZPLGM[HOME_DIR]}"
    }
    [[ ! -d "${ZPLGM[PLUGINS_DIR]}/_local---zplugin" ]] && {
        command mkdir -p "${ZPLGM[PLUGINS_DIR]}/_local---zplugin"
        # For compaudit
        command chmod go-w "${ZPLGM[PLUGINS_DIR]}"

        # Prepare mock-like plugin for Zplugin itself
        command ln -s "${ZPLGM[BIN_DIR]}/_zplugin" "${ZPLGM[PLUGINS_DIR]}/_local---zplugin"
    }
    [[ ! -d "${ZPLGM[COMPLETIONS_DIR]}" ]] && {
        command mkdir "${ZPLGM[COMPLETIONS_DIR]}"
        # For compaudit
        command chmod go-w "${ZPLGM[COMPLETIONS_DIR]}"

        # Symlink _zplugin completion into _local---zplugin directory
        command ln -s "${ZPLGM[PLUGINS_DIR]}/_local---zplugin/_zplugin" "${ZPLGM[COMPLETIONS_DIR]}"
    }
    [[ ! -d "${ZPLGM[SNIPPETS_DIR]}" ]] && {
        command mkdir "${ZPLGM[SNIPPETS_DIR]}"
        command chmod go-w "${ZPLGM[SNIPPETS_DIR]}"
    }
} # }}}
# FUNCTION: -zplg-load {{{
# Implements the exposed-to-user action of loading a plugin.
#
# $1 - plugin spec (4 formats: user---plugin, user/plugin, user, plugin)
# $2 - plugin name, if the third format is used
-zplg-load () {
    typeset -F 3 SECONDS=0
    local mode="$3"
    -zplg-any-to-user-plugin "$1" "$2"
    local user="${reply[-2]}" plugin="${reply[-1]}"

    ZPLG_SICE[$user/$plugin]=""
    -zplg-pack-ice "$user" "$plugin"
    -zplg-register-plugin "$user/$plugin" "$mode"
    if [[ "$user" != "%" && ! -d "${ZPLGM[PLUGINS_DIR]}/${user}---${plugin}" ]]; then
        (( ${+functions[-zplg-setup-plugin-dir]} )) || builtin source ${ZPLGM[BIN_DIR]}"/zplugin-install.zsh"
        if ! -zplg-setup-plugin-dir "$user" "$plugin"; then
            -zplg-unregister-plugin "$user" "$plugin"
            return
        fi
    fi

    (( ${+ZPLG_ICE[atinit]} )) && { local __oldcd="$PWD"; builtin cd "${${${(M)user:#%}:+$plugin}:-${ZPLGM[PLUGINS_DIR]}/${user}---${plugin}}" && eval "${ZPLG_ICE[atinit]}"; builtin cd "$__oldcd"; }

    -zplg-load-plugin "$user" "$plugin" "$mode"
    ZPLGM[TIME_INDEX]=$(( ${ZPLGM[TIME_INDEX]:-0} + 1 ))
    ZPLGM[TIME_${ZPLGM[TIME_INDEX]}_${user}---${plugin}]=$SECONDS
} # }}}
# FUNCTION: -zplg-load-snippet {{{
# Implements the exposed-to-user action of loading a snippet.
#
# $1 - url (can be local, absolute path)
# $2 - "--command" if that option given
# $3 - "--force" if that option given
# $4 - "-u" if invoked by Zplugin to only update snippet
-zplg-load-snippet() {
    typeset -F 3 SECONDS=0
    local -a opts tmp ice
    zparseopts -E -D -a opts f -command u i || { echo "Incorrect options (accepted ones: -f, --command)"; return 1; }
    local url="$1" correct=0
    [[ -o ksharrays ]] && correct=1

    # Remove leading whitespace and trailing /
    url="${${url#"${url%%[! $'\t']*}"}%/}"

    local filename filename0 local_dir save_url="$url"
    [[ -z "${opts[(r)-i]}" ]] && -zplg-pack-ice "$url" ""

    # - case A: called from `update --all', ZPLG_ICE not packed (above), static ice will win
    # - case B: called from `snippet', ZPLG_ICE packed, so it will win
    # - case C: called from `update', ZPLG_ICE packed, so it will win
    tmp=( "${(Q@)${(z@)ZPLG_SICE[$save_url/]}}" )
    (( ${#tmp} > 1 && ${#tmp} % 2 == 0 )) && { ice=( "${(kv)ZPLG_ICE[@]}" "${tmp[@]}" ); ZPLG_ICE=( "${ice[@]}" ); }
    tmp=( 1 )

    # Oh-My-Zsh, Prezto and manual shorthands
    (( ${+ZPLG_ICE[svn]} )) && url[1-correct,5-correct]="${ZPLG_1MAP[${url[1-correct,5-correct]}]:-${url[1-correct,5-correct]}}" || url[1-correct,5-correct]="${ZPLG_2MAP[${url[1-correct,5-correct]}]:-${url[1-correct,5-correct]}}"

    filename="${${url%%\?*}:t}"
    filename0="${${${url%%\?*}:h}:t}"
    local_dir="${url:h}"

    # Check if it's URL
    [[ "$url" = http://* || "$url" = https://* || "$url" = ftp://* || "$url" = ftps://* || "$url" = scp://* ]] && {
        local_dir="${local_dir/:\/\//--}"
    }

    # Construct a local directory name from what's in url
    local_dir="${${${${local_dir//\//--}//=/--EQ--}//\?/--QM--}//\&/--AMP--}"
    local_dir="${ZPLGM[SNIPPETS_DIR]}/${local_dir%${ZPLG_ICE[svn]---$filename0}}${ZPLG_ICE[svn]-/$filename0}"

    ZPLG_SNIPPETS[$save_url]="$filename <${${ZPLG_ICE[svn]+1}:-0}>"

    # Download or copy the file
    if [[ -n "${opts[(r)-f]}" || ! -e "$local_dir/$filename" ]]; then
        (( ${+functions[-zplg-download-snippet]} )) || builtin source ${ZPLGM[BIN_DIR]}"/zplugin-install.zsh"
        -zplg-download-snippet "$save_url" "$url" "$local_dir" "$filename0" "$filename" "${opts[(r)-u]}" || tmp=( 0 )
    fi

    (( ${+ZPLG_ICE[atinit]} && tmp[1-correct] )) && { local __oldcd="$PWD"; builtin cd "$local_dir${ZPLG_ICE[svn]+/$filename}" && eval "${ZPLG_ICE[atinit]}"; builtin cd "$__oldcd"; }

    local -a list
    if [[ -z "${opts[(r)-u]}" && -z "${opts[(r)--command]}" && "${ZPLG_ICE[as]}" != "command" ]]; then
        # Source the file with compdef shadowing
        if [[ "${ZPLGM[SHADOWING]}" = "inactive" ]]; then
            # Shadowing code is inlined from -zplg-shadow-on
            (( ${+functions[compdef]} )) && ZPLGM[bkp-compdef]="${functions[compdef]}" || builtin unset "ZPLGM[bkp-compdef]"
            functions[compdef]='--zplg-shadow-compdef "$@";'
            ZPLGM[SHADOWING]="1"
        else
            (( ++ ZPLGM[SHADOWING] ))
        fi

        # Add to fpath
        [[ -d "$local_dir/$filename/functions" ]] && {
            [[ -z "${fpath[(r)$local_dir/$filename/functions]}" ]] && fpath+=( "$local_dir/$filename/functions" )
            () {
                setopt localoptions extendedglob
                autoload $local_dir/$filename/functions/^([_.]*|prompt_*_setup|README*)(-.N:t)
            }
        }

        # Source
        if (( ${+ZPLG_ICE[svn]} == 0 )); then
            [[ ${tmp[1-correct]} = 1 && ${+ZPLG_ICE[pick]} = 0 ]] && list=( "$local_dir/$filename" )
            [[ -n ${ZPLG_ICE[pick]} ]] && list=( $local_dir/${~ZPLG_ICE[pick]}(N) ${(M)~ZPLG_ICE[pick]##/*}(N) )
        else
            if [[ -n ${ZPLG_ICE[pick]} ]]; then
                list=( $local_dir/$filename/${~ZPLG_ICE[pick]}(N) ${(M)~ZPLG_ICE[pick]##/*}(N) )
            elif (( ${+ZPLG_ICE[pick]} == 0 )); then
                list=( $local_dir/$filename/*.plugin.zsh(N) $local_dir/$filename/init.zsh(N)
                       $local_dir/$filename/*.zsh-theme(N) )
            fi
        fi

        [[ -f "${list[1-correct]}" ]] && {
            (( ${+ZPLG_ICE[silent]} )) && { builtin source "${list[1-correct]}" 2>/dev/null 1>&2; ((1)); } || builtin source "${list[1-correct]}"
            (( 1 ))
        } || { [[ ${+ZPLG_ICE[pick]} = 1 && -z ${ZPLG_ICE[pick]} ]] || echo "Snippet not loaded ($save_url)"; }

        [[ -n ${ZPLG_ICE[src]} ]] && { (( ${+ZPLG_ICE[silent]} )) && { builtin source "$local_dir${ZPLG_ICE[svn]+/$filename}/${ZPLG_ICE[src]}" 2>/dev/null 1>&2; ((1)); } || builtin source "$local_dir${ZPLG_ICE[svn]+/$filename}/${ZPLG_ICE[src]}"; }

        (( -- ZPLGM[SHADOWING] == 0 )) && { ZPLGM[SHADOWING]="inactive"; builtin setopt noaliases; (( ${+ZPLGM[bkp-compdef]} )) && functions[compdef]="${ZPLGM[bkp-compdef]}" || unfunction "compdef"; builtin setopt aliases; }
    elif [[ -n "${opts[(r)--command]}" || "${ZPLG_ICE[as]}" = "command" ]]; then
        # Subversion - directory and multiple files possible
        if (( ${+ZPLG_ICE[svn]} )); then
            if [[ -n ${ZPLG_ICE[pick]} ]]; then
                list=( $local_dir/$filename/${~ZPLG_ICE[pick]}(N) ${(M)~ZPLG_ICE[pick]##/*}(N) )
                [[ -n "${list[1-correct]}" ]] && local xpath="${list[1-correct]:h}" xfilepath="${list[1-correct]}"
            else
                local xpath="$local_dir/$filename"
            fi
        else
            local xpath="$local_dir" xfilepath="$local_dir/$filename"
            # This doesn't make sense, but users may come up with something
            [[ -n ${ZPLG_ICE[pick]} ]] && { list=( $local_dir/${~ZPLG_ICE[pick]}(N) ${(M)~ZPLG_ICE[pick]##/*}(N) ); xfilepath="${list[1-correct]}"; }
        fi
        [[ -z "${opts[(r)-u]}" && -n "$xpath" && -z "${path[(er)$xpath]}" ]] && path=( "${xpath%/}" ${path[@]} )
        [[ -n "$xfilepath" && ! -x "$xfilepath" ]] && command chmod a+x "$xfilepath" ${list[@]:#$xfilepath}
        [[ -n "${ZPLG_ICE[src]}" ]] && {
            if [[ "${ZPLGM[SHADOWING]}" = "inactive" ]]; then
                # Shadowing code is inlined from -zplg-shadow-on
                (( ${+functions[compdef]} )) && ZPLGM[bkp-compdef]="${functions[compdef]}" || builtin unset "ZPLGM[bkp-compdef]"
                functions[compdef]='--zplg-shadow-compdef "$@";'
                ZPLGM[SHADOWING]="1"
            else
                (( ++ ZPLGM[SHADOWING] ))
            fi
            (( ${+ZPLG_ICE[silent]} )) && { builtin source "$local_dir${ZPLG_ICE[svn]+/$filename}/${ZPLG_ICE[src]}" 2>/dev/null 1>&2; ((1)); } || builtin source "$local_dir${ZPLG_ICE[svn]+/$filename}/${ZPLG_ICE[src]}";
            (( -- ZPLGM[SHADOWING] == 0 )) && { ZPLGM[SHADOWING]="inactive"; builtin setopt noaliases; (( ${+ZPLGM[bkp-compdef]} )) && functions[compdef]="${ZPLGM[bkp-compdef]}" || unfunction "compdef"; builtin setopt aliases; }
        }
    fi

    # Updating – not sourcing, etc.
    [[ -n "${opts[(r)-u]}" ]] && return 0

    (( ${+ZPLG_ICE[atload]} && tmp[1-correct] )) && { local __oldcd="$PWD"; builtin cd "$local_dir${ZPLG_ICE[svn]+/$filename}" && eval "${ZPLG_ICE[atload]}"; builtin cd "$__oldcd"; }

    ZPLGM[TIME_INDEX]=$(( ${ZPLGM[TIME_INDEX]:-0} + 1 ))
    ZPLGM[TIME_${ZPLGM[TIME_INDEX]}_${save_url}]=$SECONDS
} # }}}
# FUNCTION: -zplg-compdef-replay {{{
# Runs gathered compdef calls. This allows to run `compinit'
# after loading plugins.
-zplg-compdef-replay() {
    local quiet="$1"
    typeset -a pos

    # Check if compinit was loaded
    if [[ "${+functions[compdef]}" = "0" ]]; then
        print "Compinit isn't loaded, cannot do compdef replay"
        return 1
    fi

    # In the same order
    local cdf
    for cdf in "${ZPLG_COMPDEF_REPLAY[@]}"; do
        pos=( "${(z)cdf}" )
        # When ZPLG_COMPDEF_REPLAY empty (also when only white spaces)
        [[ "${#pos[@]}" = "1" && -z "${pos[-1]}" ]] && continue
        pos=( "${(Q)pos[@]}" )
        [[ "$quiet" = "-q" ]] || print "Running compdef ${pos[*]}"
        compdef "${pos[@]}"
    done

    return 0
} # }}}
# FUNCTION: -zplg-compdef-clear {{{
# Implements user-exposed functionality to clear gathered compdefs.
-zplg-compdef-clear() {
    local quiet="$1" count="${#ZPLG_COMPDEF_REPLAY}"
    ZPLG_COMPDEF_REPLAY=( )
    [[ "$quiet" = "-q" ]] || print "Compdef-replay cleared (had $count entries)"
} # }}}
# FUNCTION: -zplg-add-report {{{
# Adds a report line for given plugin.
#
# $1 - uspl2, i.e. user/plugin
# $2, ... - the text
-zplg-add-report() {
    local uspl2="$1"
    shift
    local txt="$*"

    local keyword="${txt%% *}"
    keyword="${${${(M)keyword:#Warning:}:+${ZPLGM[col-error]}}:-${ZPLGM[col-keyword]}}$keyword${ZPLGM[col-rst]}"
    [[ -n "$uspl2" ]] && ZPLG_REPORTS[$uspl2]+="$keyword ${txt#* }"$'\n'
    [[ "${ZPLGM[DTRACE]}" = "1" ]] && ZPLG_REPORTS[_dtrace/_dtrace]+="$keyword ${txt#* }"$'\n'
} # }}}
# FUNCTION: -zplg-load-plugin {{{
# Lower-level function for loading a plugin.
#
# $1 - user
# $2 - plugin
# $3 - mode (light or load)
-zplg-load-plugin() {
    local user="$1" plugin="$2" mode="$3" correct=0
    ZPLGM[CUR_USR]="$user" ZPLG_CUR_PLUGIN="$plugin"
    ZPLGM[CUR_USPL2]="${user}/${plugin}"
    [[ -o ksharrays ]] && correct=1

    local pbase="${${${${plugin:t}%.plugin.zsh}%.zsh}%.git}"
    [[ "$user" = "%" ]] && local pdir_path="$plugin" || local pdir_path="${ZPLGM[PLUGINS_DIR]}/${user}---${plugin}"
    local pdir_orig="$pdir_path"

    if [[ "${ZPLG_ICE[as]}" = "command" ]]; then
        reply=()
        if [[ -n ${ZPLG_ICE[pick]} ]]; then
            reply=( $pdir_path/${~ZPLG_ICE[pick]}(N) ${(M)~ZPLG_ICE[pick]##/*}(N) )
            [[ -n "${reply[1-correct]}" ]] && pdir_path="${reply[1-correct]:h}"
        fi
        [[ -z "${path[(er)$pdir_path]}" ]] && {
            [[ "$mode" != "light" ]] && -zplg-diff-env "${ZPLGM[CUR_USPL2]}" begin
            path=( "${pdir_path%/}" ${path[@]} )
            -zplg-add-report "${ZPLGM[CUR_USPL2]}" "$ZPLGM[col-info2]$pdir_path$ZPLGM[col-rst] added to \$PATH"
            [[ "$mode" != "light" ]] && -zplg-diff-env "${ZPLGM[CUR_USPL2]}" end
        }
        [[ -n "${reply[1-correct]}" && ! -x "${reply[1-correct]}" ]] && command chmod a+x ${reply[@]}

        [[ -n ${ZPLG_ICE[src]} ]] && { (( ${+ZPLG_ICE[silent]} )) && { builtin source "$pdir_orig/${ZPLG_ICE[src]}" 2>/dev/null 1>&2; ((1)); } || builtin source "$pdir_orig/${ZPLG_ICE[src]}"; }
    else
        if [[ -n ${ZPLG_ICE[pick]} ]]; then
            reply=( $pdir_path/${~ZPLG_ICE[pick]}(N) ${(M)~ZPLG_ICE[pick]##/*}(N) )
        elif [[ -e "$pdir_path/${pbase}.plugin.zsh" ]]; then
            reply=( "$pdir_path/${pbase}.plugin.zsh" )
        else
            # The common file to source isn't there, so:
            -zplg-find-other-matches "$pdir_path" "$pbase"
        fi

        [[ "${#reply}" -eq "0" ]] && return 1

        # Get first one
        local fname="${reply[1-correct]:t}"
        pdir_path="${reply[1-correct]:h}"

        -zplg-add-report "${ZPLGM[CUR_USPL2]}" "Source $fname ${${${(M)mode:#light}:+(no reporting)}:-$ZPLGM[col-info2](reporting enabled)$ZPLGM[col-rst]}"

        # Light and compdef mode doesn't do diffs and shadowing
        if [[ "$mode" != "light" ]]; then
            -zplg-diff-functions "${ZPLGM[CUR_USPL2]}" begin
            -zplg-diff-options "${ZPLGM[CUR_USPL2]}" begin
            -zplg-diff-env "${ZPLGM[CUR_USPL2]}" begin
            -zplg-diff-parameter "${ZPLGM[CUR_USPL2]}" begin
        fi

        -zplg-shadow-on "${mode:-load}"

        # We need some state, but user wants his for his plugins
        (( ${+ZPLG_ICE[blockf]} )) && { local -a fpath_bkp; fpath_bkp=( "${fpath[@]}" ); }
        builtin setopt noaliases
        (( ${+ZPLG_ICE[silent]} )) && { builtin source "$pdir_path/$fname" 2>/dev/null 1>&2; ((1)); } || builtin source "$pdir_path/$fname"
        [[ -n ${ZPLG_ICE[src]} ]] && { (( ${+ZPLG_ICE[silent]} )) && { builtin source "$pdir_orig/${ZPLG_ICE[src]}" 2>/dev/null 1>&2; ((1)); } || builtin source "$pdir_orig/${ZPLG_ICE[src]}"; }
        builtin unsetopt noaliases
        (( ${+ZPLG_ICE[blockf]} )) && { fpath=( "${fpath_bkp[@]}" ); }

        -zplg-shadow-off "${mode:-load}"

        if [[ "$mode" != "light" ]]; then
            -zplg-diff-parameter "${ZPLGM[CUR_USPL2]}" end
            -zplg-diff-env "${ZPLGM[CUR_USPL2]}" end
            -zplg-diff-options "${ZPLGM[CUR_USPL2]}" end
            -zplg-diff-functions "${ZPLGM[CUR_USPL2]}" end
        fi
    fi

    (( ${+ZPLG_ICE[atload]} )) && { local __oldcd="$PWD"; builtin cd "$pdir_orig" && eval "${ZPLG_ICE[atload]}"; builtin cd "$__oldcd"; }

    # Mark no load is in progress
    ZPLGM[CUR_USR]="" ZPLG_CUR_PLUGIN="" ZPLGM[CUR_USPL2]=""
    return 0
} # }}}

#
# Dtrace
#

# FUNCTION: -zplg-debug-start {{{
# Starts Dtrace, i.e. session tracking for changes in Zsh state.
-zplg-debug-start() {
    if [[ "${ZPLGM[DTRACE]}" = "1" ]]; then
        print "${ZPLGM[col-error]}Dtrace is already active, stop it first with \`dstop'$reset_color"
        return 1
    fi

    ZPLGM[DTRACE]="1"

    -zplg-diff-functions "_dtrace/_dtrace" begin
    -zplg-diff-options "_dtrace/_dtrace" begin
    -zplg-diff-env "_dtrace/_dtrace" begin
    -zplg-diff-parameter "_dtrace/_dtrace" begin

    # Full shadowing on
    -zplg-shadow-on "dtrace"
} # }}}
# FUNCTION: -zplg-debug-stop {{{
# Stops Dtrace, i.e. session tracking for changes in Zsh state.
-zplg-debug-stop() {
    ZPLGM[DTRACE]="0"

    # Shadowing fully off
    -zplg-shadow-off "dtrace"

    # Gather end data now, for diffing later
    -zplg-diff-parameter "_dtrace/_dtrace" end
    -zplg-diff-env "_dtrace/_dtrace" end
    -zplg-diff-options "_dtrace/_dtrace" end
    -zplg-diff-functions "_dtrace/_dtrace" end
} # }}}
# FUNCTION: -zplg-clear-debug-report {{{
# Forgets dtrace repport gathered up to this moment.
-zplg-clear-debug-report() {
    -zplg-clear-report-for "_dtrace/_dtrace"
} # }}}
# FUNCTION: -zplg-debug-unload {{{
# Reverts changes detected by dtrace run.
-zplg-debug-unload() {
    if [[ "${ZPLGM[DTRACE]}" = "1" ]]; then
        print "Dtrace is still active, end it with \`dstop'"
    else
        -zplg-unload "_dtrace" "_dtrace"
    fi
} # }}}

#
# Ice support
#

# FUNCTION: -zplg-ice {{{
# Parses ICE specification (`zplg ice' subcommand), puts
# the result into ZPLG_ICE global hash. The ice-spec is
# valid for next command only (i.e. it "melts"), but it
# can then stick to plugin and activate e.g. at update.
-zplg-ice() {
    setopt localoptions extendedglob noksharrays
    local bit
    for bit; do
        [[ "$bit" = (#b)(from|proto|depth|wait|load|unload|if|blockf|svn|pick|nopick|src|bpick|as|ver|silent|mv|cp|atinit|atload|atpull|atclone|make|nomake|nosvn)(*) ]] && ZPLG_ICE[${match[1]}]="${match[2]}"
    done
} # }}}
# FUNCTION: -zplg-pack-ice {{{
# Remembers long-live ICE specs, assigns them to concrete plugin.
# Ice spec is in general forgotten for second-next command (that's
# why it's called "ice" - it melts), however some ice modifiers can
# glue to plugin mentioned in the next command.
-zplg-pack-ice() {
    (( ${+ZPLG_ICE[atclone]} )) && ZPLG_SICE[$1/$2]+="atclone ${(q)ZPLG_ICE[atclone]} "
    (( ${+ZPLG_ICE[atpull]} )) && ZPLG_SICE[$1/$2]+="atpull ${(q)ZPLG_ICE[atpull]} "
    (( ${+ZPLG_ICE[svn]} )) && ZPLG_SICE[$1/$2]+="svn ${(q)ZPLG_ICE[svn]} "
    (( ${+ZPLG_ICE[mv]} )) && ZPLG_SICE[$1/$2]+="mv ${(q)ZPLG_ICE[mv]} "
    (( ${+ZPLG_ICE[cp]} )) && ZPLG_SICE[$1/$2]+="cp ${(q)ZPLG_ICE[cp]} "
    (( ${+ZPLG_ICE[pick]} )) && ZPLG_SICE[$1/$2]+="pick ${(q)ZPLG_ICE[pick]} "
    (( ${+ZPLG_ICE[bpick]} )) && ZPLG_SICE[$1/$2]+="bpick ${(q)ZPLG_ICE[bpick]} "
    (( ${+ZPLG_ICE[as]} )) && ZPLG_SICE[$1/$2]+="as ${(q)ZPLG_ICE[as]} "
    (( ${+ZPLG_ICE[make]} )) && ZPLG_SICE[$1/$2]+="make ${(q)ZPLG_ICE[make]} "
    return 0
} # }}}
# FUNCTION: -zplg-run-task {{{
-zplg-run-task() {
    local __pass="$1" __t="$2" __tpe="$3" __idx="$4" __mode="$5" __id="${(Q)6}" __action __s=1

    local -A ZPLG_ICE
    ZPLG_ICE=( "${(@Q)${(z@)ZPLGM[WAIT_ICE_${__idx}]}}" )

    if [[ $__pass = 1 && "${ZPLG_ICE[wait]#\!}" = <-> ]]; then
        __action="${(M)ZPLG_ICE[wait]#\!}load"
    elif [[ $__pass = 1 && -n "${ZPLG_ICE[wait]#\!}" ]] && { eval "${ZPLG_ICE[wait]#\!}" || [[ $(( __s=0 )) = 1 ]]; }; then
        __action="${(M)ZPLG_ICE[wait]#\!}load"
    elif [[ -n "${ZPLG_ICE[load]#\!}" && -n $(( __s=0 )) && $__pass = 2 && -z "${ZPLG_REGISTERED_PLUGINS[(r)$__id]}" ]] && eval "${ZPLG_ICE[load]#\!}"; then
        __action="${(M)ZPLG_ICE[load]#\!}load"
    elif [[ -n "${ZPLG_ICE[unload]#\!}" && -n $(( __s=0 )) && $__pass = 1 && -n "${ZPLG_REGISTERED_PLUGINS[(r)$__id]}" ]] && eval "${ZPLG_ICE[unload]#\!}"; then
        __action="${(M)ZPLG_ICE[unload]#\!}remove"
    fi

    if [[ "$__action" = *load ]]; then
        [[ "$__tpe" = "p" ]] && -zplg-load "$__id" "" "$__mode" || -zplg-load-snippet "$__id" ""
        (( ${+ZPLG_ICE[silent]} == 0 )) && zle && zle -M "Loaded $__id"
    elif [[ "$__action" = *remove ]]; then
        (( ${+functions[-zplg-format-functions]} )) || builtin source ${ZPLGM[BIN_DIR]}"/zplugin-autoload.zsh"
        [[ "$__tpe" = "p" ]] && -zplg-unload "$__id" "" "-q"
    fi

    [[ "${REPLY::=$__action}" = \!* ]] && zle && zle .reset-prompt

    return $__s
}
# }}}
# FUNCTION: -zplg-submit-turbo {{{
-zplg-submit-turbo() {
    local tpe="$1" mode="$2" opt_uspl2="$3" opt_plugin="$4"

    ZPLGM[WAIT_IDX]=$(( ${ZPLGM[WAIT_IDX]:-0} + 1 ))
    ZPLGM[WAIT_ICE_${ZPLGM[WAIT_IDX]}]="${(j: :)${(qkv@)ZPLG_ICE}}"

    local id="${${opt_plugin:+$opt_uspl2/$opt_plugin}:-$opt_uspl2}"

    if [[ "${ZPLG_ICE[wait]}" = (\!|.|)<-> ]]; then
        ZPLG_TASKS+=( "$EPOCHSECONDS+${ZPLG_ICE[wait]#(\!|.)} $tpe ${ZPLGM[WAIT_IDX]} ${mode:-_} ${(q)id}" )
    elif [[ -n "${ZPLG_ICE[wait]}" || -n "${ZPLG_ICE[load]}" || -n "${ZPLG_ICE[unload]}" ]]; then
        ZPLG_TASKS+=( "${${ZPLG_ICE[wait]:+0}:-1} $tpe ${ZPLGM[WAIT_IDX]} ${mode:-x} ${(q)id}" )
    fi
}
# }}}
# FUNCTION: -zplugin_scheduler_add_sh {{{
# Copies task into ZPLG_RUN array, called when a task timeouts
-zplugin_scheduler_add_sh() {
    ZPLG_RUN+=( ${ZPLG_TASKS[$1]} )
    return 1
}
# }}}
# FUNCTION: -zplg-scheduler {{{
# Searches for timeout tasks, executes them
-zplg-scheduler() {
    integer __ret=$?
    sched +1 "-zplg-scheduler 1"

    integer __t=EPOCHSECONDS __i=2 correct=0
    local -a match mbegin mend

    [[ -o ksharrays ]] && correct=1

    [[ -n "$1" ]] && {
        () {
            setopt localoptions extendedglob
            ZPLG_TASKS=( ${ZPLG_TASKS[@]/(#b)([0-9+]##)(*)/${ZPLG_TASKS[$(( ${match[1-correct]} < $__t ? zplugin_scheduler_add(__i++ - correct) : __i++ ))]}} )
        }
        ZPLG_TASKS=( "<no-data>" ${(@)ZPLG_TASKS:#<no-data>} )
    } || {
        add-zsh-hook -d -- precmd -zplg-scheduler
        () {
            setopt localoptions extendedglob
            ZPLG_TASKS=( ${ZPLG_TASKS[@]/(#b)([0-9]##)(*)/$(( ${match[1-correct]} <= 1 ? ${match[1-correct]} : __t ))${match[2-correct]}} )
        }
    }

    local __task __idx=0 __count=0 __idx2
    for __task in ${ZPLG_RUN[@]}; do
        -zplg-run-task 1 "${(@z)__task}" && ZPLG_TASKS+=( "$__task" )
        [[ $(( ++__idx, __count += ${${REPLY:+1}:-0} )) -gt 20 ]] && break
    done
    for (( __idx2=1; __idx2 <= __idx; ++ __idx2 )); do
        -zplg-run-task 2 "${(@z)ZPLG_RUN[__idx2-correct]}"
    done
    ZPLG_RUN[1-correct,__idx-correct]=()

    return $__ret
}
# }}}

#
# Main function with subcommands
#

# FUNCTION: zplugin {{{
# Main function directly exposed to user, obtains subcommand
# and its arguments, has completion.
zplugin() {
    [[ "$1" != "ice" ]] && {
        local -a ice
        ice=( "${(kv)ZPLG_ICE[@]}" )
        ZPLG_ICE=()
        local -A ZPLG_ICE
        ZPLG_ICE=( "${ice[@]}" )
    }

    local -a match mbegin mend
    local MATCH; integer MBEGIN MEND

    case "$1" in
       (load|light)
           (( ${+ZPLG_ICE[if]} )) && { eval "${ZPLG_ICE[if]}" || return 0; }
           if [[ -z "$2" && -z "$3" ]]; then
               print "Argument needed, try help"
           else
               if [[ -n ${ZPLG_ICE[wait]} || -n ${ZPLG_ICE[load]} || -n ${ZPLG_ICE[unload]} ]]; then
                   -zplg-submit-turbo p "$1" "$2" "$3"
               else
                   -zplg-load "$2" "$3" "${1/load/}"
               fi
           fi
           ;;
       (snippet)
           (( ${+ZPLG_ICE[if]} )) && { eval "${ZPLG_ICE[if]}" || return 0; }
           if [[ -n ${ZPLG_ICE[wait]} || -n ${ZPLG_ICE[load]} || -n ${ZPLG_ICE[unload]} ]]; then
               -zplg-submit-turbo s "" "$2" "$3"
           else
               ZPLG_SICE[${2%/}/]=""
               -zplg-load-snippet "$2" "$3"
           fi
           ;;
       (ice)
           shift
           -zplg-ice "$@"
           ;;
       (cdreplay)
           -zplg-compdef-replay "$2"
           ;;
       (cdclear)
           -zplg-compdef-clear "$2"
           ;;
       (dstart|dtrace)
           -zplg-debug-start
           ;;
       (dstop)
           -zplg-debug-stop
           ;;
       (man)
           man "${ZPLGM[BIN_DIR]}/doc/zplugin.1"
           ;;
       (*)
           (( ${+functions[-zplg-format-functions]} )) || builtin source ${ZPLGM[BIN_DIR]}"/zplugin-autoload.zsh"
           case "$1" in
               (zstatus)
                   -zplg-show-zstatus
                   ;;
               (times)
                   -zplg-show-times
                   ;;
               (self-update)
                   -zplg-self-update
                   ;;
               (unload)
                   (( ${+functions[-zplg-unload]} )) || builtin source ${ZPLGM[BIN_DIR]}"/zplugin-unload.zsh"
                   if [[ -z "$2" && -z "$3" ]]; then
                       print "Argument needed, try help"
                   else
                       [[ "$2" = "-q" ]] && { 5="-q"; shift; }
                       # Unload given plugin. Cloned directory remains intact
                       # so as are completions
                       -zplg-unload "$2" "${3:#-q}" "${${(M)4:#-q}:-${(M)3:#-q}}"
                   fi
                   ;;
               (update)
                   (( ${+ZPLG_ICE[if]} )) && { eval "${ZPLG_ICE[if]}" || return 0; }
                   if [[ "$2" = "--all" || ( -z "$2" && -z "$3" ) ]]; then
                       [[ -z "$2" ]] && { echo "Assuming --all is passed"; sleep 2; }
                       -zplg-update-or-status-all "update"
                   else
                       -zplg-update-or-status "update" "$2" "$3"
                   fi
                   ;;
               (status)
                   if [[ "$2" = "--all" || ( -z "$2" && -z "$3" ) ]]; then
                       [[ -z "$2" ]] && { echo "Assuming --all is passed"; sleep 2; }
                       -zplg-update-or-status-all "status"
                   else
                       -zplg-update-or-status "status" "$2" "$3"
                   fi
                   ;;
               (report)
                   if [[ "$2" = "--all" || ( -z "$2" && -z "$3" ) ]]; then
                       [[ -z "$2" ]] && { echo "Assuming --all is passed"; sleep 3; }
                       -zplg-show-all-reports
                   else
                       -zplg-show-report "$2" "$3"
                   fi
                   ;;
               (loaded|list)
                   # Show list of loaded plugins
                   -zplg-show-registered-plugins "$2"
                   ;;
               (clist|completions)
                   # Show installed, enabled or disabled, completions
                   # Detect stray and improper ones
                   -zplg-show-completions "$2"
                   ;;
               (cclear)
                   # Delete stray and improper completions
                   -zplg-clear-completions
                   ;;
               (cdisable)
                   if [[ -z "$2" ]]; then
                       print "Argument needed, try help"
                   else
                       local f="_${2#_}"
                       # Disable completion given by completion function name
                       # with or without leading "_", e.g. "cp", "_cp"
                       if -zplg-cdisable "$f"; then
                           (( ${+functions[-zplg-forget-completion]} )) || builtin source ${ZPLGM[BIN_DIR]}"/zplugin-install.zsh"
                           -zplg-forget-completion "$f"
                           print "Initializing completion system (compinit)..."
                           builtin autoload -Uz compinit
                           compinit
                       fi
                   fi
                   ;;
               (cenable)
                   if [[ -z "$2" ]]; then
                       print "Argument needed, try help"
                   else
                       local f="_${2#_}"
                       # Enable completion given by completion function name
                       # with or without leading "_", e.g. "cp", "_cp"
                       if -zplg-cenable "$f"; then
                           (( ${+functions[-zplg-forget-completion]} )) || builtin source ${ZPLGM[BIN_DIR]}"/zplugin-install.zsh"
                           -zplg-forget-completion "$f"
                           print "Initializing completion system (compinit)..."
                           builtin autoload -Uz compinit
                           compinit
                       fi
                   fi
                   ;;
               (creinstall)
                   (( ${+functions[-zplg-install-completions]} )) || builtin source ${ZPLGM[BIN_DIR]}"/zplugin-install.zsh"
                   # Installs completions for plugin. Enables them all. It's a
                   # reinstallation, thus every obstacle gets overwritten or removed
                   [[ "$2" = "-q" ]] && { 5="-q"; shift; }
                   -zplg-install-completions "$2" "$3" "1" "${(M)4:#-q}"
                   [[ -z "${(M)4:#-q}" ]] && print "Initializing completion (compinit)..."
                   builtin autoload -Uz compinit
                   compinit
                   ;;
               (cuninstall)
                   if [[ -z "$2" && -z "$3" ]]; then
                       print "Argument needed, try help"
                   else
                       (( ${+functions[-zplg-forget-completion]} )) || builtin source ${ZPLGM[BIN_DIR]}"/zplugin-install.zsh"
                       # Uninstalls completions for plugin
                       -zplg-uninstall-completions "$2" "$3"
                       print "Initializing completion (compinit)..."
                       builtin autoload -Uz compinit
                       compinit
                   fi
                   ;;
               (csearch)
                   -zplg-search-completions
                   ;;
               (compinit)
                   (( ${+functions[-zplg-forget-completion]} )) || builtin source ${ZPLGM[BIN_DIR]}"/zplugin-install.zsh"
                   -zplg-compinit
                   ;;
               (dreport)
                   -zplg-show-debug-report
                   ;;
               (dclear)
                   -zplg-clear-debug-report
                   ;;
               (dunload)
                   -zplg-debug-unload
                   ;;
               (compile)
                   (( ${+functions[-zplg-compile-plugin]} )) || builtin source ${ZPLGM[BIN_DIR]}"/zplugin-install.zsh"
                   if [[ "$2" = "--all" || ( -z "$2" && -z "$3" ) ]]; then
                       [[ -z "$2" ]] && { echo "Assuming --all is passed"; sleep 2; }
                       -zplg-compile-uncompile-all "1"
                   else
                       -zplg-compile-plugin "$2" "$3"
                   fi
                   ;;
               (uncompile)
                   if [[ "$2" = "--all" || ( -z "$2" && -z "$3" ) ]]; then
                       [[ -z "$2" ]] && { echo "Assuming --all is passed"; sleep 2; }
                       -zplg-compile-uncompile-all "0"
                   else
                       -zplg-uncompile-plugin "$2" "$3"
                   fi
                   ;;
               (compiled)
                   -zplg-compiled
                   ;;
               (cdlist)
                   -zplg-list-compdef-replay
                   ;;
               (cd)
                   -zplg-cd "$2" "$3"
                   ;;
               (delete)
                   -zplg-delete "$2" "$3"
                   ;;
               (edit)
                   -zplg-edit "$2" "$3"
                   ;;
               (glance)
                   -zplg-glance "$2" "$3"
                   ;;
               (changes)
                   -zplg-changes "$2" "$3"
                   ;;
               (recently)
                   shift
                   -zplg-recently "$@"
                   ;;
               (create)
                   -zplg-create "$2" "$3"
                   ;;
               (stress)
                   -zplg-stress "$2" "$3"
                   ;;
               (-h|--help|help|"")
                   -zplg-help
                   ;;
               (ls)
                   shift
                   -zplg-ls "$@"
                   ;;
               (*)
                   print "Unknown command \`$1' (use \`help' to get usage information)"
                   ;;
            esac
            ;;
    esac
} # }}}

#
# Source-executed code
#

zmodload zsh/datetime
functions -M -- zplugin_scheduler_add 1 1 -zplugin_scheduler_add_sh
autoload add-zsh-hook
add-zsh-hook -- precmd -zplg-scheduler

# code {{{
builtin unsetopt noaliases
builtin alias zpl=zplugin zplg=zplugin

-zplg-prepare-home

# Simulate existence of _local/zplugin plugin
# This will allow to cuninstall of its completion
ZPLG_REGISTERED_PLUGINS+=( "_local/zplugin" )
ZPLG_REGISTERED_PLUGINS=( "${(u)ZPLG_REGISTERED_PLUGINS[@]}" )
ZPLG_REGISTERED_STATES[_local/zplugin]="1"

# Add completions directory to fpath
fpath=( "${ZPLGM[COMPLETIONS_DIR]}" "${fpath[@]}" )

# Colorize completions for commands unload, report, creinstall, cuninstall
zstyle ':completion:*:zplugin:argument-rest:plugins' list-colors '=(#b)(*)/(*)==1;35=1;33'
zstyle ':completion:*:zplugin:argument-rest:plugins' matcher 'r:|=** l:|=*'
# }}}
