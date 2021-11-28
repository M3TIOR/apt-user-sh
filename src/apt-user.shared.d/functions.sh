# shellcheck shell=sh
# @file - functions.sh
# @brief - Shared functions for the apt-user.sh suite.
# NOTE: No code involved in this script should call functions outside this script.
#       This code is intended to be portable between applications, not static.
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
## Functions

abrt() { error "Error in '$SELF': $*"; exit 1; }

# @describe - Prints the simplest primitive type of a value.
# @usage - typeof [-g] VALUE
# @param "-g" - Toggles the numerical return values which increase in order of inclusivity.
# @param VALUE - The value you wish to check.
# @prints (5|'string') - When no other primitive can be coerced from the input.
# @prints (4|'filename') - When a string primitive is safe to use as a filename.
# @prints (3|'alphanum') - When a string primitive only contains letters and numbers.
# @prints (2|'double') - When the input can be coerced into a floating number.
# @prints (1|'int') - When the input can be coerced into a regular integer.
# @prints (0|'uint') - When the input can be coereced into an unsigned integer.
typeof()
(
	SIGNED=false; FLOATING=false; GROUP=false; f=''; b=''; # in='';

	# Check for group return parameter.
	if test "$1" = "-g"; then GROUP=true; shift; fi;

	in="$*";

	# Check for negation sign.
	if test "$in" != "${b:=${in#-}}"; then SIGNED=true; fi;
	in="$b"; b='';

	# Check for floating point.
	if test "$in" != "${b:=${in#*.}}" -a "$in" != "${f:=${in%.*}}"; then
		if test "$in" != "$f.$b"; then
			if $GROUP; then echo "5"; else echo "string"; fi; return;
		fi;
		FLOATING=true;
	fi;

	case "$in" in
		''|*[!0-9\.]*)
			if test "$in" != "${in#*[~\`\!@\#\$%\^\*()\+=\{\}\[\]|:;\"\'<>,?\/]}"; then
				if $GROUP; then echo "5"; else echo "string"; fi;
			else
				if test "$in" != "${1#*[_\-.\\ ]}"; then
					if $GROUP; then echo "4"; else echo "filename"; fi;
				else
					if $GROUP; then echo "3"; else echo "alphanum"; fi;
				fi;
			fi;;
		*)
			if $FLOATING; then
				if $GROUP; then echo "2"; else echo "double"; fi; return;
			fi;
			if $SIGNED; then
				if $GROUP; then echo "1"; else echo "int"; fi; return;
			fi;
			if $GROUP; then echo "0"; else echo "uint"; fi;
		;;
	esac;
)

# @describe - Ensures any character can be used as raw input to a shell pattern.
# @usage sanitize_quote_escapes STRING('s)...
# @param STRING('s) - The string or strings you wish to sanitize.
sanitize_pattern_escapes()
(
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
)

# @describe - Ensures any characters that are embeded inside quotes can
#             be `eval`ed without worry of XSS / Parameter Injection.
# @usage [-p COUNT] sanitize_quote_escapes STRING('s)...
# @param STRING('s) - The string or strings you wish to sanitize.
# @param COUNT - The number of passes to run sanitization, default is 1.
sanitize_quote_escapes()
(
	DONE=''; PASSES=1; l=0; f=''; c=''; # TODO='';

	if test "$1" = '-p'; then PASSES="$2"; shift 2; fi;

	TODO="$*"; # must be set after the conditional shift.

	OIFS="$IFS";
	while test "$l" -lt "$PASSES"; do
		# Ensure we cycle TODO after the first pass.
		if test "$l" -gt 0; then TODO="$DONE"; DONE=; fi;

		# Use IFS to split by filter chars.
		IFS='"\$'; for f in $TODO; do
			# Since $f cannot contain unsafe chars, we can test against it.
			c=;
			if test "${TODO#${DONE}${f}\"}" != "$TODO"; then c='\"'; fi;
			if test "${TODO#${DONE}${f}\\}" != "$TODO"; then c='\\'; fi;
			if test "${TODO#${DONE}${f}\$}" != "$TODO"; then c='\$'; fi;
			if test "${TODO#${DONE}${f}\`}" != "$TODO"; then c='\`'; fi;
			DONE="$DONE$f$c";
		done;
		l="$((l + 1))"; # Increment loop counter.
	done;
	IFS="$OIFS";

	printf '%s' "$DONE";
)

uniques_of()
(
	RESULTS="";
	for VAR in $*; do
		for INNER in $RESULTS; do
			if test "$VAR" = "$INNER"; then
				continue 1; # Should continue the outer loop.
			fi;
		done;
		RESULTS="$RESULTS $VAR";
	done;

	printf "%s" "$RESULTS";
)

query_yn() {
	while read -p 'y/N: ' YN; do
		case "$YN" in
			[yY]*) return 0;;
			[nN]*) return 1;;
			*) echo "Improper response, please type 'yes', or 'no'.";;
		esac;
	done;
}

nop(){ return 0; }

# @describe - Handles return of variables through values. This ensures that
#     globally managed variables don't get out of hand, poluting the hashmap,
#     and causing otherwise unforseen bugs.
v_return(){
	# NOTE: unset all possible return values to ensure there's no return polution.
	#       RETURN, is reserved for status code returns.
	unset RETURN1; unset RETURN2; unset RETURN3; unset RETURN4; unset RETURN5;
	unset RETURN6; unset RETURN7; unset RETURN8; unset RETURN9;
	local VALUE; local COUNTER;
	COUNTER=1;

	# $@ ensures proper expansion of double quoted objects.
	for VALUE in $@; do
		if test "$COUNTER" -gt 9; then return 1; fi;
		eval "RETURN${COUNTER}=\"$VALUE\";";
		COUNTER=$((COUNTER+1));
	done;
}

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
			i) INCLUSIVE="1";;
			a) ASYNC="$OPTARG";;
			t) EMULATE_TYPE="1";;
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
	while read line; do
		# The sysadmin shouldn't put a lowercase PATH in, because posix
		# environment variables are case sensitive.
		VAR=${line%=*}; if test "$VAR" = "PATH"; then
			# Trim off useless garbage.
			line=${line#*=}; line=${line#\"}; line=${line%\"};
			OIFS="$IFS";
			IFS=":";
			for p in $line; do
				PATH="$PATH:$NEWROOT/$p";
			done;
			IFS="$OIFS";
			PATH="$PATH:$NEWROOT";
			PATH=${PATH#:}; # Remove the unnecessary prefix in a post process.
		fi;

	done < /etc/environment

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

	OIFS="$IFS"; IFS=":"; for p in $OLD_LD_P; do
		LD_LIBRARY_PATH="$NEWROOT/$p:$LD_LIBRARY_PATH";
	done; IFS="$OIFS";

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
