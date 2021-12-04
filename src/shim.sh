#!/bin/sh
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

# @brief - Emulates a chroot executable search without sandboxing.
# @usage - pseudochroot [-i] [-a FILE] [-t] NEWROOT PROGRAM [ARGS...]
# @param [-i] - Instead of replacing the PATH, it's appended to.
# @param [-a] - Launches the command asynchronusly, puts the PID in FILE
# @param [-t] - Emulate the `type` POSIX command, don't run PROGRAM.
# @description - Uses the environment variables:
#     PATH, CPATH, LD_LIBRARY_PATH, LIBRARY_PATH, and PKG_CONFIG_PATH
#   to emulate the effect of a binary being called within a chroot, without
#   actually changing the root directory.
# NOTE: this depends on the `setsid` utility.
pseudochroot()
(
	OPTARG=''; OPTIND=0;
	INCLUSIVE=''; ASYNC=''; EMULATE_TYPE='';
	NEWROOT=''; PROGRAM='';

	while getopts iat option; do
		case "$option" in
			"i") INCLUSIVE="1";;
			"a") ASYNC="$OPTARG";;
			"t") EMULATE_TYPE="1";;
		esac;
	done;

	# clear getopts parsed args so we can access positional args by index.
	shift $(($OPTIND-1));

	if test -d "$1"; then
		NEWROOT="$1";
		shift;
	else
		printf '%s' "'$1' is not a directory." >&2; return 1;
	fi;

	PROGRAM="$1"; shift;

	# Since this is in a subshell, to be exclusive, just empty the variable
	# before filling it.
	if test -z "$INCLUSIVE"; then PATH=''; fi;
	for p in $(. /etc/environment; IFS=":"; echo "$PATH"); do
		PATH="$PATH:$NEWROOT/$p";
	done;
	PATH="$PATH:$NEWROOT";
	PATH=${PATH#:}; # Remove the unnecessary prefix in a post process.

	# Don't forget to add user's binaries.
	if test -d "$HOME/.local/bin"; then
		PATH="$HOME/.local/bin:$PATH";
	fi;

	if test -n "$EMULATE_TYPE"; then
		# If were' in emulate type mode, we just ensure the program exists in the
		# result PATH.
		PATH="$PATH" type "$PROGRAM" && return $?;
	else
		if ! PATH="$PATH" type "$PROGRAM"; then
			error "Couldn't find command '$PROGRAM' within chroot";
			return 1;
		fi;
	fi;


	OLD_LD_P="$(get_ld_library_paths | tr '\n' ':')"; OLD_LD_P="${OLD_LD_P#.:}";
	if test -n "$INCLUSIVE"; then LD_LIBRARY_PATH="$OLD_LD_P"; fi;

	for p in $(IFS=":"; echo "$OLD_LD_P"); do
		LD_LIBRARY_PATH="$NEWROOT/$p:$LD_LIBRARY_PATH";
	done;

	OLD_LD_P="${OLD_LD%:}";

	# LD_LIBRARY_PATH is for Loading time. LIBRARY_PATH is for linking time.
	# They're the same, just used at different times by different processes.
	LIBRARY_PATH="$LD_LIBRARY_PATH";


	# NOTE: non-generative solutions are below. These are niche variables that
	#       may need fixing in the future, but they should be fine for now.

	if test -z "$INCLUSIVE"; then CPATH=''; fi;
	CPATH="$PSEUDOCHROOT/usr/include:$CPATH"; # modern include dir
	CPATH="$PSEUDOCHROOT/include:$CPATH"; # legacy include dir
	CPATH=${CPATH%:};

	if test -z "$INCLUSIVE"; then PKG_CONFIG_PATH=''; fi;
	PKG_CONFIG_PATH="$NEWROOT/usr/lib/x86_64-linux-gnu/pkgconfig:$PKG_CONFIG_PATH";
	PKG_CONFIG_PATH="$NEWROOT/usr/lib/pkgconfig:$PKG_CONFIG_PATH";
	PKG_CONFIG_PATH="$NEWROOT/usr/share/pkgconfig:$PKG_CONFIG_PATH";
	PKG_CONFIG_PATH=${PKG_CONFIG_PATH%:};


	if test -z "$ASYNC"; then
		PATH="$PATH" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" LIBRARY_PATH="$LIBRARY_PATH" \
		CPATH="$CPATH" PKG_CONFIG_PATH="$PKG_CONFIG_PATH" \
		command "$PROGRAM" $*;

		return "$?";
	else
		# NOTE: uses setsid instead of "&" shell async, because "&" leaves a
		#       dangling shell PID which would lock up our `.profile`.
		PATH="$PATH" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" LIBRARY_PATH="$LIBRARY_PATH" \
		CPATH="$CPATH" PKG_CONFIG_PATH="$PKG_CONFIG_PATH" \
		setsid "$PROGRAM" $*;

		PID="$!";
		echo "$PID" > "$ASYNC";
		return 0;
	fi;
)

# @describe - Ensures any character can be used as raw input to a shell pattern.
# @usage sanitize_quote_escapes STRING('s)...
# @param STRING('s) - The string or strings you wish to sanitize.
sanitize_pattern_escapes()
{
	DONE=''; f=''; b=''; c=''; # TODO='';

	TODO="$*";

	OIFS="$IFS"; # Use IFS to split by filter chars.
	IFS='"\$[]*'; for f in $TODO; do
		# Since $f cannot contain unsafe chars, we can test against it.
		c=;
		if test "${TODO#${DONE}${f}\\}" != "$TODO"; then c='\\'; fi;
		if test "${TODO#${DONE}${f}\$}" != "$TODO"; then c='\$'; fi;
		if test "${TODO#${DONE}${f}\*}" != "$TODO"; then c='\*'; fi;
		# test "${TODO#${DONE}${f}\)}" = "$TODO" || c='\)';
		# test "${TODO#${DONE}${f}\(}" = "$TODO" || c='\(';
		if test "${TODO#${DONE}${f}\[}" != "$TODO"; then c='\['; fi;
		if test "${TODO#${DONE}${f}\]}" != "$TODO"; then c='\]'; fi;
		DONE="$DONE$f$c";
	done;
	IFS="$OIFS";

	printf '%s' "$DONE";
}

bindargs()
{
	CHROOT="${XDG_DATA_HOME:-$HOME/.local/share}/apt-user/root";

	# Only bind paths which binaries depend on; configuration paths
	# should be handled by root, though additional bind parameters may be
	# passed by the user through BINDS
	printf "%s\n" "-b $CHROOT/bin:/bin";
	printf "%s\n" "-b $CHROOT/lib:/lib";
	printf "%s\n" "-b $CHROOT/usr:/usr";

	# NOTE: it's hard to know whether these libary folders are stable
	#       between architectures; I don't think they are, based on my experience
	#       with cross compilation and quemu so that's something to remember
	#       for future bugs including either cross compilation or different host
	#       architectures besides x86_64 systems like the one I'm building on.
	printf "%s\n" "-b $CHROOT/lib32:/lib32";
	printf "%s\n" "-b $CHROOT/lib64:/lib64";
	printf "%s\n" "-b $CHROOT/libx32:/libx32";

	for bind in $(IFS=";"; echo "$BINDS"); do
		printf "%s\n" "-b $bind";
	done;
}

this()
{
	SELF="$(readlink -n "$0")";
	APPDATA="${XDG_DATA_HOME:-$HOME/.local/share}/apt-user";
	CHROOT="$APPDATA/root";
	BINDIR="$APPDATA/bin";

	printf "%s\n" "$CHROOT/${SELF#$(sanitize_pattern_escapes "$BINDIR")}";
}

# We want this to be inclusive because the root may have installed our
# predicate packages for us; this may not be standalone.
alias proot="pseudochroot -i ${XDG_DATA_HOME:-$HOME/.local/share}/apt-user/root proot";

# This exports all environment variables in the scope of the shim, effectively
# passing through any variables handed over individually. It's kinda hacky,
# unfortunately this also re-sets every shell function as well which is a lot
# of unnecessary overhead.
set -a; eval "$(set)" 2>/dev/null; set +a;

proot $(bindargs) "$(this)" $*;
