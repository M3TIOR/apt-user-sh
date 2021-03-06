#!/bin/sh
# @file - shim.sh
# @brief - Provides access to isolated apt-user installed binaries.
# @copyright - (C) 2021  Ruby Allison Rose
# SPDX-License-Identifier: GPL-3.0-only

### Linter Directives ###
# shellcheck shell=sh

################################################################################

# @brief - Prints the locations LD_LIBRARY_PATH looks for by default.
# @description - Parses the internals of /etc/ld.so.cache and reduces the
#     paths to those which all the cached libraries are found within.
#
# NOTE: This may not be the best generative solution; it might be better to
#       parse /etc/ld.so.conf and reduce to paths that exits from that.
#       I guess I won't find out until someone files a bug report.
get_ld_library_paths() {
	# In Ubuntu at least, needs GNU findutils, binutils, and coreutils. :\
	# Every other solution uses more niche commands or takes absolutely forever
	# to run. SORRY THIS ISN'T AS PORTABLE AS I'D LIKE IT TO BE (;n;)
	strings /etc/ld.so.cache | xargs dirname | sort -u;
}

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
		PATH="$PATH" command -V "$PROGRAM" && return $?;
	else
		if ! PATH="$PATH" command -v "$PROGRAM" >/dev/null; then
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
	APPDATA="${XDG_DATA_HOME:-$HOME/.local/share}/apt-user";
	MOUNT="$APPDATA/mnt";
	CHROOT="$APPDATA/root";

	# Only bind paths which binaries depend on; configuration paths
	# should be handled by root, though additional bind parameters may be
	# passed by the user through BINDS
	printf "%s\n" "-b $MOUNT/bin:/bin";
	printf "%s\n" "-b $MOUNT/usr:/usr";

	# NOTE: it's hard to know whether these libary folders are stable
	#       between architectures; I don't think they are, based on my experience
	#       with cross compilation and quemu so that's something to remember
	#       for future bugs including either cross compilation or different host
	#       architectures besides x86_64 systems like the one I'm building on.
	for libfolder in "$MOUNT"/lib*; do
		printf "%s\n" "-b $libfolder:/$(basename $libfolder)";
	done;

	for bind in $(IFS=";"; echo "$BINDS"); do
		printf "%s\n" "-b $bind";
	done;
}

this()
{
	SELF="$(realpath -s "$0")";
	APPDATA="${XDG_DATA_HOME:-$HOME/.local/share}/apt-user";
	MOUNT="$APPDATA/mnt";
	BINDIR="$APPDATA/bin";

	printf "%s\n" "$MOUNT/${SELF#$(sanitize_pattern_escapes "$BINDIR")}";
}

# We want this to be inclusive because the root may have installed our
# predicate packages for us; this may not be standalone.
alias proot="pseudochroot -i ${XDG_DATA_HOME:-$HOME/.local/share}/apt-user/root proot";

# This exports all environment variables in the scope of the shim, effectively
# passing through any variables handed over individually. It's kinda hacky.
# Unfortunately this also re-sets every shell function as well which is a lot
# of unnecessary overhead.
set -a; eval "$(set)" 2>/dev/null; set +a;

exec proot $(bindargs) "$(this)" $*;
