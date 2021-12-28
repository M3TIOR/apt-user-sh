# @file - setup.sh
# @brief - Shared setup code for the apt-user.sh suite.
# @copyright - (C) 2021  Ruby Allison Rose
# SPDX-License-Identifier: GPL-3.0-only

### Linter Directives ###
# shellcheck shell=sh
# shellcheck disable=SC2059,SC2034

################################################################################
## Globals

VERSION="0.2"; # Should be included in all scripts.
APPDATA="${XDG_DATA_HOME:-$HOME/.local/share}/apt-user";
MOUNT="$APPDATA/mnt";
CHROOT="$APPDATA/root";
BINDIR="$APPDATA/bin";

# BUGFIX: Prevents nested shells from being unable to log.
LOGFILE="${LOGFILE:-$TMP/${APPNAME}.$$.log}";

# Record initial FDs for processing later.
FD1="$(readlink -n -f /proc/$$/fd/1)";
FD2="$(readlink -n -f /proc/$$/fd/2)";

if test "$FD1" != "${FD1#/dev/pts/}"; then
	PTS="${FD1#/dev/pts/}";
fi;

################################################################################
## Functions

setup_cleanup(){
	if test "$VERBOSE" -gt "0"; then rm -f "$LOGFILE.2"; fi;
	if test "$VERBOSE" -gt "1"; then rm -f "$LOGFILE.1"; fi;
}

if test -z "$NO_COLOR"; then
	# When we have ANSI compliance use the normal polyfill.
	echo(){
		# NOTE: Added argument '-a' for inline ANSI support.

		# Allow us to use getopts multiple times without the global getopts or
		# prior getopts instantiations breaking our execution through the OPTIND var.
		local OPTARG;            OPTARG='';
		local OPTIND;            OPTIND=0;
		local DISABLE_NEWLINE;   DISABLE_NEWLINE=0;
		local ANSI_COLOR;        ANSI_COLOR='';
		local FD1='';

		while getopts na:- option; do
			case "$option" in
				'n') DISABLE_NEWLINE=1;;
				'a') ANSI_COLOR="$OPTARG";;
				'-') break;;
			esac
		done

		# clear getopts parsed args so we can access positional args by index.
		shift $(($OPTIND-1));

		if test -z "$ANSI_COLOR"; then
			printf '%b' "$*";
		else
			printf '%b' "\033[${ANSI_COLOR}m";
			printf '%b' "$*";
			printf '%b' "\033[0m";
		fi;

		# if flag is not zero then true. IE print newline unless flag set
		if test $DISABLE_NEWLINE -eq 0; then printf '\n'; fi;
	}
else
	# If ANSI is disabled use this function instead which just has
	# the ANSI option do nothing. Filters out ANSI escape code hell on
	# machines that don't support it.
	# NOTE: The code is almost identical to that of the above just minified.
	echo(){
		local OPTARG; local OPTIND; local DISABLE_NEWLINE; local ANSI_COLOR;
		OPTARG=''; OPTIND=0; DISABLE_NEWLINE=0; ANSI_COLOR="";
		while getopts na: option; do case "$option" in
		'n') DISABLE_NEWLINE=1;;
		'a') ANSI_COLOR="$OPTARG";;
		'-') break;; esac; done; shift $(($OPTIND-1));
		printf '%b' "$*"; if test "$DISABLE_NEWLINE" -eq "0"; then printf '\n'; fi;
	}
fi;

error() { echo -a 31 "Error: $@" >&3; }
warning() { echo -a 33 "Warning: $@" >&4; }
info() { echo -a 34 "Info: $@" >&5; }
debug() { echo -a 35 "Debug: $@" >&6; }

################################################################################
## Main Script

# NOTE: This should execute prior to all other code besides global variables
#       and function definitions.

# Redirect to logfiles; Don't use logfile if piping, otherwise we break
# the pipe. Pick up the log, redirecting it to the terminal if we have one.
FD="${FD1##*/}"; FD="${FD%:*}";
if test "$FD" != "pipe"; then
	exec 1>>"$LOGFILE.1";

	if test -n "$FD1" -a "$FD1" != "/dev/null" -a "$FD1" != "$LOGFILE.1"; then
		tail --pid="$$" -f "$LOGFILE.1" >> "$FD1" & trap "kill $!;" 0;
	fi;
fi;
FD="${FD2#*/}"; FD="${FD%:*}";
if test "$FD" != "pipe"; then
	exec 2>>"$LOGFILE.2";

	if test -n "$FD2" -a "$FD2" != "/dev/null" -a "$FD2" != "$LOGFILE.2"; then
		tail --pid="$$" -f "$LOGFILE.2" >> "$FD2" & trap "kill $!;" 0;
	fi;
fi;

# XXX: Fixes a racing condition caused by the shared logging setup.
# NOTE: Yes, this needs to be 100 millis Ruby, don't modify this any lower
#       or you'll introduce a new bug that takes you hours to solve again.
sleep 0.1;

# NOTE: Log levels: 0 = silent; 1 = error; 2 = warning; 3 = info; 4 = debug;
exec 3>&2; exec 4>&2; exec 5>&2; exec 6>&2;
for FD in `seq 6 -1 $((VERBOSE+3))`; do
	eval "exec $FD>/dev/null";
done;

if test $VERBOSE -gt 4; then # Silly mode
	# Print every line the shell is executing along with the result.
	# This is hyper verbose and challenging to read, but it can help when all
	# else has failed.
	PS4="\$SELF in PID#\$\$ @\$LINENO: ";
	set -x;
	trap "set >&2;" 0;
fi;

trap "setup_cleanup;" 0;
