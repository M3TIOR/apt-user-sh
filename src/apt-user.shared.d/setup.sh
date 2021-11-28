# shellcheck shell=sh
# @file - setup.sh
# @brief - Shared setup code for the apt-user.sh suite.
###############################################################################
# Copyright 2020 Ruby Allison Rose (aka. M3TIOR)
#
# Permission is hereby granted, free of charge, to any person obtaining a
# copy of this software and associated documentation files (the "Software"),
# to deal in the Software without restriction, including without limitation
# the rights to use, copy, modify, merge, publish, distribute, sublicense,
# and/or sell copies of the Software, and to permit persons to whom the
# Software is furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
# OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.

################################################################################
## Globals

# SELF=; # The path to the currently executing script.

# shellcheck disable=SC2059,SC2034
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

# Redirect to logfiles.
exec 1>>"$LOGFILE.1";
exec 2>>"$LOGFILE.2";

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

# And this will pick up the log, redirecting it to the terminal if we have one.
if test -n "$FD1" -a "$FD1" != "/dev/null" -a "$FD1" != "$LOGFILE.1"; then
	tail --pid="$$" -f "$LOGFILE.1" >> "$FD1" & trap "kill $!;" 0;
fi;
if test -n "$FD2" -a "$FD2" != "/dev/null" -a "$FD2" != "$LOGFILE.2"; then
	tail --pid="$$" -f "$LOGFILE.2" >> "$FD2" & trap "kill $!;" 0;
fi;

# XXX: Fixes a racing condition caused by the shared logging setup.
sleep 0.01;

trap "setup_cleanup;" 0;
