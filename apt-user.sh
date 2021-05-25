#!/bin/sh -e
# NOTE: Needs `chmod u+x` to function properly.
# NOTE; This script is not intended to be sourced.
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
## POLYFILLS
if test -z "$NO_COLOR"; then
	# When we have ANSI compliance use the normal polyfill.
	echo(){
		# NOTE: Added argument '-a' for inline ANSI support.

		# Allow us to use getopts multiple times without the global getopts or
		# prior getopts instantiations breaking our execution through the OPTIND var.
		local OPTARG;            OPTARG='';
		local OPTIND;            OPTIND=0;
		local DISABLE_NEWLINE;   DISABLE_NEWLINE=0;
		local ANSI_COLOR;        ANSI_COLOR="";

		while getopts na:- option; do
			case "$option" in
				n) DISABLE_NEWLINE=1;;
				a) ANSI_COLOR="$OPTARG";;
				-) break;;
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
		n) DISABLE_NEWLINE=1;;
		a) ANSI_COLOR="$OPTARG";; esac; done; shift $(($OPTIND-1));
		printf '%s' "$*"; if test "$DISABLE_NEWLINE" -eq "0"; then printf '\n'; fi;
	}
fi;

################################################################################
## UNIVERSALS

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

# @describe - This function wraps a command to ensure its flag was captured,
#     and it doesn't halt the process when being called from the global scope.
#
# NOTE: Only error codes on the global scope trigger a failure when `set -e`
capture_status(){
	unset RETURN; $@; RETURN=$?; return 0;
	# ALT: If this breaks, you can do the below as an alternative implementation.
	#      The snippit below should be able to run in the global scope too.
	#RETURN=0; $@ || RETURN=$?;
}

starts_with(){
	local STR;   STR="$1";
	local QUERY; QUERY="$2";
	test "${STR#$QUERY}" != "$STR";
	return $?; # This may be redundant, but I'm doing it anyway for my sanity.
}

ends_with(){
	local STR;   STR="$1";
	local QUERY; QUERY="$2";
	test "${STR%$QUERY}" != "$STR";
	return $?;
}

uniques_of(){
	local RESULTS; RESULTS="";
	local VAR; local INNER;
	for VAR in $*; do
		for INNER in $RESULTS; do
			if test "$VAR" = "$INNER"; then
				continue 1; # Should continue the outer loop.
			fi;
		done;
		RESULTS="$RESULTS $VAR";
	done;

	printf "%s" "$RESULTS";
}

glob_match() {
	local RESULT;
	local RETURN; RETURN=0;
	for RESULT in $*; do
		if ends_with $RESULT "\*"; then
			RETURN=$((RETURN + 1));
		else
			echo "$RESULT ";
		fi;
	done;

	return $RETURN;
}

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

################################################################################
## FUNCTIONS

error() { echo -a 31 "$@" >&3; }
warning() { echo -a 33 "$@" >&4; }
info() { echo -a 34 "$@" >&5; }
debug() { echo -a 35 "$@" >&6; }
# cmd_log() {
# 	local COMMAND; COMMAND=$1; shift;
# 	$@ 1>$TEMPDIR/fifo1 &
# 	while read line; do
# 		$COMMAND "$line";
# 	done < $TEMPDIR/fifo1;
# }
# cmd_log_error(){ cmd_log error; }
# cmd_log_warning(){ cmd_log warning; }
# cmd_log_info(){ cmd_log info; }
# cmd_log_debug(){ cmd_log debug; }

# NOTE: should always run upon exit because we have a temp dir to clean up.
cleanup() {
	# Make sure the unionfs is down, then remove the container.
	info "Running cleanup script...";
	if test -n "$FUSE"; then
		# NOTE: Must use killall because unionfs spawns multiple theads, and
		#       killing the parent, isn't enough to fully unmount the FS.
		if ps -C unionfs-fuse -o pid= > /dev/null; then
			# Checks if unionfs-fuse has a running process id before killing.
			info "Killing UnionFS...";
			killall -w unionfs-fuse -n $FUSE;
		else
			error "Error: UnionFS wasn't initiated, please file a bug report with";
			error "       contents of 'VERBOSE=6 apt-local.sh {your command here}'.";
		fi;
		unset FUSE;
	fi;
	rm $BVF -rf $TEMPDIR;
	info "Done";
}

list_missing_fixable_dependencies() {
	# NOTE: this is now manually maintained, I don't think automating the parsing
	#       of arguments, would be very worth my time here.
	#
	# NOTE: hopefully none of these require datafiles or post install config.
	#       `dpkg` doesn't run config scripts when using the extract feature.


	# TODO: May be Ubuntu specific, need to validate for Debian and others.
	if ! pseudochroot -i -t $USER_CONTAINER unionfs-fuse; then
		echo -n "unionfs-fuse ";
	fi;

	# TODO: same as above.
	if ! pseudochroot -i -t $USER_CONTAINER proot; then
		echo -n "proot ";
	fi;

	# util-linux package contains lslocks on most distros.
	if ! pseudochroot -i -t $USER_CONTAINER lslocks; then
		echo -n "util-linux ";
	fi;

	# psmisc is similar to util-linux, but contains killall
	if ! pseudochroot -i -t $USER_CONTAINER killall; then
		echo -n "psmisc ";
	fi;

	# This may be exclusive to ubuntu, find out.
	if ! pseudochroot -i -t $USER_CONTAINER ps; then
		echo -n "procps ";
	fi;
}

install_dependencies() {
	local REAR;
	local TARGET_LIST;

	mkdir $BVF -p $TEMPDIR/downloads;

	warning "Warning: Fetching unmet dependency list...";
	# Damn I wish I could figure out how to make this code look better.
	# NOTE: apt-get install -d finds unmet dependencies.
	# NOTE: `-o APT::Get::Download` prevents system configuration from preventing
	#       network fetch requests.
	# NOTE: `apt-get install --print-uris` will fail if the package is already
	#       in the cache. So try and find a local copy if it turns up nothing.
	#       `-o Dir::Cache::Archives` prevents pre-downloaded cache files from
	#       messing up the resolver.
	apt-get install \
		-o APT::Get::Download="1" \
		-o Dir::Cache::Archives="$TEMPDIR/downloads" \
		-d --print-uris $* > $TEMPDIR/fifo1 &

	# TODO: Use file descriptors and extra files in the temporary folder
	#       instead of our fifos and grep. Removing dependencies.
	# You can use apt-get's stable CLI output and shell string trimming to sort;
	# lines starting with "'" are packages!
	cat $TEMPDIR/fifo1 | grep ".deb" > $TEMPDIR/fifo2 &
	while read TRIPLE; do
		REAR=${TRIPLE#* };
		TARGET_LIST="$TARGET_LIST ${REAR%%_*}";
	done < $TEMPDIR/fifo2;

	# When our resolver's found packages applicable for download, grab them.
	cd $TEMPDIR/downloads;
	# Can be called without root and apt.conf doesn't interfere.
	# fetches dependencies to $PWD
	if type apt > /dev/null; then
		apt download $TARGET_LIST;
	elif type apt-get > /dev/null; then
		apt-get download $TARGET_LIST;
	fi;
	# NOTE: dash stores an OLDPWD so you can use `cd -` to return to the last PWD.
	cd -;

	# echo before loop to dedicate line to the below.
	echo;
	local FILENAME;
	for deb in $TEMPDIR/downloads/*.deb; do
		FILENAME="${deb##*/}";
		warning -n "\rWarning: Installing dependency ${FILENAME%%_*}";

		dpkg -x $deb $APPLICATION_DATA/dependencies;
	done;
	info "\rInfo: Done installing dependencies.";
}

ensure() {
	local OPTARG; OPTARG='';
	local OPTIND; OPTIND=0;
	local ENSURE_FILE;

	while getopts f option; do
		case "$option" in
			f) ENSURE_FILE=1;;
		esac;
	done;

	shift $(($OPTIND-1));

	for ARG in $*; do
		if test -n "$ENSURE_FILE"; then
			mkdir -p $BVF ${ARG%/*} 1>&6 2>&3;
			if touch $ARG 1>&6 2>&3; then
				# Assume on error, touch will throw an error for us.
				echo "touch: created file '$ARG'" >&6;
			fi;
		fi;
	done;
}

# @brief - Emulates a chroot executable search.
# @description - Uses the environment variables:
#     PATH, CPATH, LD_LIBRARY_PATH, LIBRARY_PATH, and PKG_CONFIG_PATH
#   to emulate the effect of a binary being called within a chroot, without
#   actually changing the root directory.
#
#   The `-i` or `--inclusive` argument may be supplied before the target
#   chroot directory to make the lookup passive, if the appropriate binary
#   can't be found in the chroot, then pseudochroot will use an external system
#   binary where possible.
pseudochroot() {
	# TODO: Implement a generative solution that can be applied to more
	#       envrionments for portability.
	# NOTE: I don't want to bloat the PATH with unnecessary search locations,
	#       because that makes programs take longer to execute in the shell.
	#       So this needs to look for the minimum, APT chain managed PATH.
	#       User modifications should be limited to their HOME directory or
	#       system administrator modifications.
	#
	# TODO: Figure out XDG nonesense. (as a part of the above)
	#
	# No need XDG garbage, only look at /etc/environment for the PATH
	# initializer, mod that, then add the user local bin conditionally.

	local OPTARG; OPTARG='';
	local OPTIND; OPTIND=0;
	local INCLUSIVE;
	local ASYNC;
	local EMULATE_TYPE;
	local LAST_SEGMENT;
	local PROGRAM;
	local PSEUDOCHROOT;

	while getopts iat option; do
		case "$option" in
			i) INCLUSIVE="1";;
			a) ASYNC="1";;
			t) EMULATE_TYPE="1";;
		esac;
	done

	# clear getopts parsed args so we can access positional args by index.
	shift $(($OPTIND-1));

	if test -d "$1"; then
		PSEUDOCHROOT="$1"; shift;
	else
		error "Error: Directory not found '$1'";
		return 1;
	fi;

	PROGRAM="$1"; shift;

	debug "Modifying PATH";

	# NOTE: append in reverse order, because you're appending to the front.
	LAST_SEGMENT=`test -n "$INCLUSIVE" && echo "$PATH"`;
	local PATH; PATH="$LAST_SEGMENT";

	local VAR;
	while read line; do
		VAR=${line%=*};
		# The sysadmin shouldn't put a lowercase PATH in, because posix
		# environment variables are case sensitive.
		if test "$VAR" = "PATH"; then
			# Trim off useless garbage.
			line=${line#*=}; line=${line#\"}; line=${line%\"};
			OIFS=$IFS;
			IFS=":";
			for p in $line; do
				PATH="$PSEUDOCHROOT/$p:$PATH";
			done;
			IFS=$OIFS;
			PATH="$PSEUDOCHROOT:$PATH";
			PATH=${PATH%:}; # Remove the last suffix in a post process.
		fi;

	done < /etc/environment

	# Don't forget to add user's binaries.
	if test -d "$HOME/.local/bin"; then
		PATH="$HOME/.local/bin:$PATH";
	fi;

	if test -n "$EMULATE_TYPE"; then
		# If were' in emulate type mode, we just ensure the program exists in the
		# result PATH.
		PATH=$PATH type $PROGRAM >&6 && return $?;
	else
		if ! PATH=$PATH type $PROGRAM >&6; then
			error "Error: Couldn't find command '$PROGRAM' within chroot";
			return 1;
		fi;
	fi;

	LAST_SEGMENT=`test -n "$INCLUSIVE" && echo ":$CPATH"`;
	local CPATH;
	CPATH="$PSEUDOCHROOT/usr/include$LAST_SEGMENT"; # modern include dir
	CPATH="$PSEUDOCHROOT/include:$CPATH"; # legacy include dir


	LAST_SEGMENT=`test -n "$INCLUSIVE" && echo ":$LD_LIBRARY_PATH"`;
	local LD_LIBRARY_PATH;
	# TODO: research why /usr/lib comes before /lib. In debian they're both
	#       system paths. Looks the same for Ubuntu.
	LD_LIBRARY_PATH="$PSEUDOCHROOT/usr/lib$LAST_SEGMENT";
	LD_LIBRARY_PATH="$PSEUDOCHROOT/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH";
	LD_LIBRARY_PATH="$PSEUDOCHROOT/lib:$LD_LIBRARY_PATH";
	LD_LIBRARY_PATH="$PSEUDOCHROOT/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH";


	LAST_SEGMENT=`test -n "$INCLUSIVE" && echo ":$LIBRARY_PATH"`;
	local LIBRARY_PATH;
	LIBRARY_PATH="$PSEUDOCHROOT/lib$LAST_SEGMENT";
	LIBRARY_PATH="$PSEUDOCHROOT/lib/x86_64-linux-gnu:$LIBRARY_PATH";
	LIBRARY_PATH="$PSEUDOCHROOT/usr/lib:$LIBRARY_PATH";
	LIBRARY_PATH="$PSEUDOCHROOT/usr/lib/x86_64-linux-gnu:$LIBRARY_PATH";


	LAST_SEGMENT=`test -n "$INCLUSIVE" && echo ":$PKG_CONFIG_PATH"`;
	local PKG_CONFIG_PATH;
	PKG_CONFIG_PATH="$PSEUDOCHROOT/usr/lib/x86_64-linux-gnu/pkgconfig$LAST_SEGMENT";
	PKG_CONFIG_PATH="$PSEUDOCHROOT/usr/lib/pkgconfig:$PKG_CONFIG_PATH";
	PKG_CONFIG_PATH="$PSEUDOCHROOT/usr/share/pkgconfig:$PKG_CONFIG_PATH";


	# Should run this command without destroying the global ENV.
	debug "Debug: Calling pseudochroot with '$PROGRAM $*'";
	PATH="$PATH" CPATH="$CPATH" LD_LIBRARY_PATH="$LD_LIBRARY_PATH" \
	LIBRARY_PATH="$LIBRARY_PATH" PKG_CONFIG_PATH="$PKG_CONFIG_PATH" \
	$PROGRAM $@ & PSCHR_PID=$!;

	if test -z "$ASYNC"; then
		wait $PSCHR_PID; return $?;
	else
		debug "Debug: Launched asynchronusly, child PID#$PSCHR_PID";
		return 0;
	fi;
}

# @brief - Executes the passed executable and arguments within a 100%
#          user owned RWX privilage chroot.
# @description - Uses a UnionFS Filesystem in User Space (FUSE) and
#   `proot` to create a 100% user owned chroot environment for executing
#   commands. In this script it's only intended to be used for APT and
#   tidying calls.
#
#   It's built to download it's own dependencies as needed, so there's no extra
#   setup for users.
containerize() {
	local OPTARG; OPTARG='';
	local OPTIND; OPTIND=0;
	local FAKE_ROOT;

	while getopts R option; do
		case "$option" in
			R) FAKE_ROOT="-0";;
		esac;
	done;

	# clear getopts parsed args so we can access positional args by index.
	shift $(($OPTIND-1));

	info "Info: Containerizing Command '$*'";

	# Dont' allow multiple unionfs-fuse sessions to run at once.
	if test -z "$FUSE"; then
		# Only make the mountpoint if we need it.
		mkdir $BVF -p $MOUNTPOINT;

		info "Info: Starting UnionFS FUSE...";
		pseudochroot -i -a $APPLICATION_DATA/dependencies \
			unionfs-fuse $FSV \
				-o fsname=apt-local \
				-o uid=$UID \
				-o auto_unmount \
				-o cow \
				-f \
				$USER_CONTAINER=RW:/=RO \
				$MOUNTPOINT;

		# Intercept from pseudochroot
		FUSE=$PSCHR_PID;

		# Track unionizer PID to kill after process end. INFO log level.
		info "Info: UnionFS started with PID#$FUSE";
	fi;

	# NOTE: This is a workaround due to a racing condition happening since we have
	#       no native way of waiting for unionfs-fuse to alert us when we've
	#       actually mounted the FS properly.
	#
	# XXX: There's no way I can guarantee that each system will implement the fs
	#      type name, the same way, so I used multiple `-t type` options as an
	#      attempt to cover all possibilities. But that may create a BUG l8r.
	local TEST_UNIONFS;
	TEST_UNIONFS="df -t fuse.unionfs-fuse -t fuse.unionfs -t fuse";
	while ! $TEST_UNIONFS $MOUNTPOINT 1>/dev/null 2>/dev/null; do sleep 0.1; done;

	# NOTE: proot verbosity should be included in Silly Mode.
	# XXX: Unfortunately apt and apt-get force require root for installing
	#      packages. I wanted this to be done without even faking root,
	#      so there wouldn't be any issues with file permissions down the road.
	capture_status pseudochroot -i $APPLICATION_DATA/dependencies \
		proot -v $((VERBOSE-5)) --cwd="$CWD" \
			-b "/etc/host.conf" \
			-b "/etc/hosts" \
			-b "/etc/nsswitch.conf" \
			-b "/dev/" \
			-b "/sys/" \
			-b "/proc/" \
			-b "/tmp/" \
			-b "$HOME" \
			$FAKE_ROOT -r $MOUNTPOINT $*;
}

sanitize_aptget() {
	local FLAG_ARGS; local POSITIONALS;
	while test "$#" -gt 0; do
		# The version and help flags override everything else, so we can
		# exit early, and pass directly to the command.
		if test "$1" = "--version" || test "$1" = "-v" ||
		   test "$1" = "--help" || test "$1" = "-h"; then
			return 1;
		fi;
		if starts_with "$1" "-"; then
			# None of the apt-get flags take parameters, so this is easy.
			FLAG_ARGS="$FLAG_ARGS $1";
		else
			POSITIONALS="$POSITIONALS $1";
		fi;
		shift;
	done;

	# XXX: returning with an empty variable may cause issues.
	v_return "$FLAG_ARGS" "$POSITIONALS";
}

packages_are() {
	local RETURN="";

	# NOTE: '/var/lib/dpkg/info/' holds information files for all installed
	#       debian packages. Files are stored with names matching the binary
	#       package name searchable in apt, and have suffixes for their
	#       function. '[package].list' files contain a log of all the files
	#       modified / installed by the package. If it exists, the package
	#       should be installed.
	case $1 in
		"installed") shift;
			for PACKAGE in $*; do
				if ! -e "$USER_CONTAINER/var/lib/dpkg/info/$PACKAGE.list"; then
					RETURN="$PACKAGE $RETURN";
				fi;
			done;
		;;
		"uninstalled") shift;
			for PACKAGE in $*; do
				if -e "$USER_CONTAINER/var/lib/dpkg/info/$PACKAGE.list"; then
					RETURN="$PACKAGE $RETURN";
				fi;
			done;
		;;
		*)
			v_return "$1";
			return 2;
		;;
	esac;

	# When we have packages not matching the target state, return them
	if test -n "$RETURN"; then
		v_return "$RETURN"; # Should get passed to RETURN1;
		return 1;
	fi;
}

packages_for() {
	local PACKAGE;
	local RESULTS; local FAILURES; local ARG;

	for ARG in $*; do
		if test -d $ARG; then
			# Attempts to use shell variable expeansion to search recursively.
			if ! packages_for $ARG/*; then
				FAILURES="$FAILURES $RETURN2";
			fi;
			RESULTS="$RESULTS $RETURN1";
			continue;
		elif test -h $ARG; then # Same as readlink; only matches symlinks.
			# readlink won't fail, but dpkg still can.
			if PACKAGE=`dpkg -S \`readlink -n $ARG\``; then
				RESULTS="$RESULTS ${PACKAGE%%:*}"; continue;
			fi;
		elif test -e $ARG; then
			if PACKAGE=`dpkg -S $ARG`; then
				RESULTS="$RESULTS ${PACKAGE%%:*}"; continue;
			fi;
		fi;
		FAILURES="$FAILURES $ARG";
	done;

	RESULTS=`uniques_of $RESULTS`;

	# C-like variable returns.
	v_return $RESULTS $FAILURES;

	if test -n "$FAILURES"; then
		return 1;
	fi;
}

is_unlocked() {
	local LOCKPID;
	# NOTE: lslocks is the only good candidate for this, because it can print
	#       root locks from an unprivleged state. We have to guarantee there's
	#       as little faking root as possible. IMHO doing that is a security flaw.
	pseudochroot -i $APPLICATION_DATA/dependencies \
		lslocks -rn --output COMMAND,PID >> $TEMPDIR/fifo1 &

	grep 'apt' < $TEMPDIR/fifo1 >> $TEMPDIR/fifo2 &

	local LOCKINFO; local LOCKUID;
	while read LOCKINFO; do
		# All we need to do here, is make sure neither the current user or root are
		# using dpkg / apt. There shouldn't be side effects for other regular users
		# since this is package does most everything in a container.
		#
		# TODO:
		# XXX: Should probably guard this with a test query, in case there's a race
		#      between the next `ps` call and lslocks' capture value. If the process
		#      is gone, ps will break the result with an unhandled error.
		LOCKUID=`ps -o uid= -p ${LOCKINFO#* }`;
		if test "$LOCKUID" -ne 0 && test "$LOCKUID" -ne $UID; then
			return 1;
		fi;

	done < $TEMPDIR/fifo2;
	wait $LOCKPID;
}

sync_control_file() {
	# NOTE: unfortuantely, dpkg uses a single control file scheme, which is
	#       incompatable with automatic updates from the unionfs. This implements
	#       an update system. It pulls all changes from the system admin control
	#       file into the user control file without overwriting user managed
	#       package metadata.
	local LINE; local SKIP; local DIFFSTATUS;

	# Only updates the control file if there have been changes made by root.
	if test -e $APPLICATION_DATA/dpkg-system-status.old; then
		diff $APPLICATION_DATA/dpkg-system-status.old /var/lib/dpkg/status > /dev/null 2> /dev/null;
		DIFFSTATUS=$?;
		if test $DIFFSTATUS -eq 1; then
			return 1;
		fi;
	fi;

	# NOTE: this tries to reduce the window of time which this funciton is
	#       vulnerable to race conditions introduced by the system package store.
	cp $BVF /var/lib/dpkg/status $TEMPDIR/dpkg-system-status.new;

	rm $BVF $APPLICATION_DATA/dpkg-status;
	touch $APPLICATION_DATA/dpkg-status;

	# The current algorithm will use a two pass system. It's very inefficient.
	# TODO: make this faster.
	local OLDIFS; OLDIFS="$IFS";
	IFS="";
	while read LINE; do
		IFS="$OLDIFS";
		if test -n "$SKIP"; then
			if test -z "$LINE"; then
				SKIP="";
				# Ensure replacement of newline into control file.
				echo >> $APPLICATION_DATA/dpkg-status;
			fi;
		elif starts_with "$LINE" "Package: " &&
		   test -e "$USER_CONTAINER/var/lib/dpkg/info/${LINE#Package: }.list"; then
			# This first pass should concatenate all system packages not in the chroot
			# to the intermediary file.
			SKIP="1";
		else
			# Append lines into the intermediary file.
			echo -- "$LINE" >> $APPLICATION_DATA/dpkg-status;
		fi;
		IFS=""; # reset IFS before next `read` cycle
	done < $TEMPDIR/dpkg-system-status.new;

	while read LINE; do
		IFS="$OLDIFS";

		if test -n "$SKIP"; then
			if test -z "$LINE"; then
				SKIP="";
				printf "\n" >> $APPLICATION_DATA/dpkg-status;
			fi;
		elif starts_with "$LINE" "Package: " &&
		     test ! -e "$USER_CONTAINER/var/lib/dpkg/info/${LINE#Package: }.list"; then
			# This second pass should push all local package metadata down into the
			# intermediary file.
			SKIP="1";
		else
			printf "$LINE\n" >> $APPLICATION_DATA/dpkg-status;
		fi;

		IFS="";
	done < $USER_CONTAINER/var/lib/dpkg/status;
	IFS="$OLDIFS";

	# Migrate the new status file to the old one.
	cp $BVF -u $TEMPDIR/dpkg-system-status.new $APPLICATION_DATA/dpkg-system-status.old;

	# Then, finally we need to copy over the intermediary into the user container
	# so the contained dpkg and apt suite can see the system package changes and
	# accomidate for them.
	cp $BVF -u $APPLICATION_DATA/dpkg-status $USER_CONTAINER/var/lib/dpkg/status;

	return 0;
}

update_held_packages() {
	# NOTE: Only limit packages managed by the user to those which don't affect
	#       system services and admin level functionality.
	#
	# NOTE: things to hold:
	#         * any kernels
	#         * init systems (systemd, ...)
	#         * initrd / ram startup filesystems
	#         * bootloaders ()
	#         * privilage excalation devices (sudo, pkexec...)
	#       basically any other package that modifies administrator stuff.
	#
	# /vmlinuz - is a link to the kernel on debian based systems.
	# /sbin/init - points to the init system in most standard systems.
	# /usr/sbin/grub* - is a matcher to all possible grub helpers.
	#
	# TODO: figure out better error handeling.
	local STAGED; local GLOBMATCHES;
	packages_for /vmlinuz /sbin/init;
	STAGED="$RETURN1"; # concat successfully discovered packages into the stage.
	packages_for `glob_match /usr/sbin/grub*`;
	STAGED="$STAGED $RETURN1";

	containerize -R apt-mark hold $STAGED >&6;
}

################################################################################
## MAIN

## Globals (Comprehensive)
a="/`readlink -f $0`"; a=${a%/*}; a=${a#/}; a=${a:-.}; PROCDIR=$(cd "$a"; pwd);
TEMPDIR=`mktemp -p /tmp -d apt-local-unionfs-XXXXXXXXX`;
VERBOSE=${VERBOSE-2}; # NOTE: this is assinging a default of 2, not subtracting.
APT_GET=apt;
# BVF=; # Coreutils Verbose Flag (empty when off, `-v` when on)
# FSV=; # UnionFS Verbose Flag (empty when off, `-d -o debug` when on)
# UID=; # POSIX User ID (set based on execution privilage)
# NO_COLOR=; # Instructs programs not to output in color (user supplied);
# OIFS=; # Old Input Field Separator (shell environment storage)
# COMMAND=; # The current command the user is trying to run.
# MISSING_DEPENDS=; # A list of all dependencies not installed at startup.
# FUSE=; # The UnionFS FUSE PID once daemonized.
# RETURN1=;...RETURN9=; Reserved C-like function return variables.
# RETURN=; Reserved alternate storage location for exit codes.


# Load external common variables.
. $PROCDIR/common.sh

# NOTE: Log levels: 0 = silent; 1 = error; 2 = warning; 3 = info; 4 = debug;
# NOTE: these don't need their own files because they're fifo pipes.
# NOTE: NOTE: NOTE: Script verbose flags should not affect APT output.
exec 3>&2; exec 4>&2;
exec 5>&1; exec 6>&1;
for FD in `seq 6 -1 $((VERBOSE+3))`; do
	# TODO: see if this can be done without eval;
	#       It's just better when thing's don't use eval;
	eval "exec $FD>/dev/null";
done;

# Executes at DEBUG verbosity.
if test $VERBOSE -gt 3; then
	# Should make every "busybox" and "coreutils" command verbose when ran.
	BVF="-v";
	# When debug verbosity, make sure unionfs is verbose too.
	USV="-d -o debug";
fi;

if test $VERBOSE -gt 4; then # Silly mode
	# Print every line the shell is executing along with the result.
	# This is hyper verbose and challenging to read, but it can help when all
	# else has failed.
	set -x;
fi;


# BUG: exiting manually (HUP - KILL) causes the cleanup script to run twice.
trap "cleanup" EXIT HUP INT QUIT ABRT KILL;

# Early exit, don't waste time with extra setup if we don't need it.
# NEEDS coreutils: that's the only package this can't download for itself.
if ! type apt-get >&6 || \
   ! type apt-mark >&6 || \
   ! type apt-cache >&6 || \
   ! type dpkg >&6 || \
   ! type dpkg-deb >&6 || \
   ! type dpkg-query >&6 || \
	 ! type mkdir >&6 || \
	 ! type grep >&6; then
	error "Error: Couldn't find a required binary on your system.";
	error "       To see more info, call the script with 'VERBOSE=4'";
	error "       and try making sure the 'coreutils' package is installed.";
	exit 1;
fi;
if ! type apt >&6; then
	warning "Warning: Couldn't find APT, some colored output will be disabled.";
	APT_GET=apt-get;
fi;
if ! type add-apt-repository >&6; then
	info "Info: Missing optional, the 'add-repository' command will be disabled.";
fi;

if ! UID=`id -u` 1>/dev/null 2>/dev/null; then
	error "Error: Failed to fetch UID of caller.";
	error "       Running 'chmod u+x {this_script}' should fix this.";
fi;


## INITIALIZE DIRECTORIES
mkdir $BVF -p $APPLICATION_DATA;
mkdir $BVF -p $APPLICATION_DATA/dependencies;
mkfifo $TEMPDIR/fifo1;
mkfifo $TEMPDIR/fifo2;


if ! test -d "$USER_CONTAINER"; then
	info "Info: Initializing new container...";
	mkdir $BVF -p $USER_CONTAINER;

	# NOTE: should only make DPKG and the APT suite useable.
	ensure -f \
		$USER_CONTAINER/var/lib/dpkg/lock \
		$USER_CONTAINER/var/lib/dpkg/lock-frontend \
		$USER_CONTAINER/var/lib/dpkg/triggers/Lock \
		$USER_CONTAINER/var/lib/apt/lists/lock \
		$USER_CONTAINER/var/cache/apt/lock \
		$USER_CONTAINER/var/cache/apt/archives/lock \
		$USER_CONTAINER/var/cache/debconf/passwords.dat;

	# NOTE: essential folders will also need to be initialized, to correctly set
	#       the file ownership and privilage metadata.
	ensure \
		$USER_CONTAINER/var/lib/apt/lists/partial \
		$USER_CONTAINER/var/cache/apt/archives/partial;
fi;


MISSING_DEPENDS=`list_missing_fixable_dependencies`;
if test -n "$MISSING_DEPENDS"; then
	install_dependencies $MISSING_DEPENDS;
fi;

if ! is_unlocked; then
	error "Error: You're already running an instanced of apt-user, or your";
	error "       sysadmin is running an apt command and the root is locked.";
	error "        --> try again later when that has finished <--";
	exit 100;
fi;

COMMAND="$1"; shift;

warning "Warning: Syncing 'dpkg' control files.";
if sync_control_file; then
	warning "Warning: Updating held packages.";
	if ! update_held_packages; then
		warning "Warning: Couldn't update held packages; it's inadvisable to run";
		warning "         'apt-local full-upgrade' in this state. For more info";
		warning "         see 'VERBOSE=4 apt-local ...'";

		if test "$COMMAND" = "full-upgrade"; then
			echo "Are you sure you want to run 'full-upgrade' in this state?";
			echo "This will probably always cause unnecessary bloat.";
			if ! query_yn; then
				exit 100;
			fi;
		fi;
	fi;
fi;

# NOTE: adjusts apt-get to supress Autoremove warnings.
# TODO: implement local AUTOREMOVE eligibility notification.
APT_GET="$APT_GET -o APT::Get::HideAutoRemove=1";

warning "Warning: Checking for broken packages introduced by the sysadmin...";
containerize -R $APT_GET install -q --fix-broken --yes >&5;
if ! test "$?" -eq 0; then
	error "Error: Couldn't fix broken packages, run 'VERBOSE=4 apt-local ...'";
	error "       for more information and consider submitting a bug report.";
fi;


case "$COMMAND" in
	# TODO: if I can't only list packages with updates from the user container,
	#       then don't list any at all.
	'list')
		containerize -R dpkg-query --list $*;
	;;
	'search')
		if type apt > /dev/null && test -z "$NO_COLOR"; then
			containerize -R apt search $*;
		else
			containerize -R apt-cache search $*;
		fi;
	;;
	'show')
		if type apt > /dev/null && test -z "$NO_COLOR"; then
			containerize -R apt show $*;
		else
			containerize -R apt-cache show $*;
		fi;
	;;
	'install')
		# NOTE: I want users to be able to install newer packages over
		#       unmaintained system packages / copy existing packages installed
		#       in the system to their own container, for version isolation when
		#       desired. --reinstall should allow package isolation,
		containerize -R $APT_GET install $*;

		# TODO: check packages for external resources, and  add them to a list
		#       for which the binaries will be managed with update-alternatives
		#       so they can automatically be run within the chroot.
		#       This will remove the need to have the exec function at all
		#       and reduce the need for advanced user intervention.
	;;
	'upgrade')
		containerize -R $APT_GET upgrade $*;
	;;
	'full-upgrade')
		# NOTE: I want this to differ from the system full-upgrade, as
		#       a full upgrade to the user's container, shouldnt' involve any
		#       upgrades of system packages unrelated to packages installed
		#       within the user container. This needs to only upgrade packages
		#       directly in the user container, and depended upon by the user
		#       container.
		#
		#       If users want to update system packages, they can do so
		#       explicitly using 'upgrade'. Otherwise this could cause
		#       unnecessary bloat.
		#
		# TODO: maybe consider using apt to resolve the immediate dependencies
		#       and update those too. But nothing else.

		SEARCH=$USER_CONTAINER/var/lib/dpkg/info/*.list;
		if ! ends_with "$SEARCH" '*.list'; then
			for FILEPATH in $SEARCH; do
				FILENAME="${FILEPATH##*/}";
				PACKAGES="$PACKAGES ${FILENAME%.list}";
			done;
		fi;

		containerize -R $APT_GET upgrade $PACKAGES $*;
	;;
	'purge'|'remove')
		# TODO: Only remove packages installed within the user chroot
		if sanitize_aptget $*; then
			if packages_are installed $RETURN2; then
				containerize -R $APT_GET $COMMAND $*;
			else
				error "Error: Couldn't find the following packages installed in the";
				error "       user container -> $RETURN1";
			fi;
		else
			containerize -R $APT_GET $COMMAND $*;
		fi;
	;;
	'autoremove')
		# TODO: don't actually call `autoremove`; use conditional `remove`
		#       to only remove packages installed within the chroot
		#       DO use `autoremove` as a resolver to find which packages are
		#       eligable for removal.
		containerize -R $APT_GET autoremove $*;
	;;
	'clean'|'update')
		# NOTE: no sync needed here, everything belongs to the user.
		containerize -R $APT_GET $COMMAND $*;
	;;

	'edit-sources')
		# Shouldn't need root to access the sources file.
		if test -n "$EDITOR"; then
			containerize $EDITOR /etc/apt/sources.list; exit $RETURN;
		elif type editor >&6; then
			# There may be a dpkg managed editor link using update-alternatives.
			containerize editor /etc/apt/sources.list;
		else
			echo "Error: Couldnt' find a suitable editor to edit the apt sources.";
			exit 1;
		fi;
	 ;;

	# TODO: add user update-alternatives functionality to improve binary compat.

	# QOL COMMANDS
	'exec')
		# NOTE: It may be a good idea to prevent users from calling apt-get
		#       or other internals from exec as they could screw up the package
		#       state or bloat their machine. Especially considering at least
		#       apt-get should be fully accessible from this frontend.
		#
		# TODO: protect users from hyper omega fucking things up by holding
		#       packages like with INSTALL
		#
		# TODO: use env overrides to protect the env from fakeroot.
		if test "$1" = "-g"; then
			true; # TODO: make -g remove paths added by export-paths.
		else
			containerize $*; exit $RETURN;
		fi;
	;;
	'has-installed')
		# TODO: test automate check all packages in argument list.
		# NOTE: this is currently unfinished, it doesn't yet exclude system packages.
		if ! packages_are installed $@; then
			printf "%s\n" "$RETURN2";
		else
			exit 0;
		fi;
	;;
	'--help')
	echo "Usage: apt-local COMMAND ...";
	echo;
	echo "'apt-local' is a script that provides APT features in a multi-user environment";
	echo "friendly way. It creates user specific packages and apt caches using a unionfs";
	echo "chroot, and provides the same functionality as specialized APT tools.";
	echo;
	echo "available APT commands:";
	# NOTE: Use escape sequence instead of inline tabs because it's explicit
	#       Not everyone uses an editor that shows them whitespace characters.
	echo "\tlist - list packages based on package names";
	echo "\tsearch - search in package descriptions";
	echo "\tshow - show package details";
	echo "\tinstall - install packages";
	echo "\tremove - remove packages";
	echo "\tpurge - remove packages and configuration data";
	echo "\tautoremove - Remove automatically all unused packages";
	echo "\tupdate - update list of available packages";
	echo "\tupgrade - upgrade the system by installing/upgrading packages";
	echo "\tfull-upgrade - upgrade the system by removing/installing/upgrading";
	echo "\tedit-sources - edit the source information file";
	echo;
	echo "QOL commands added by yours truely:";
	echo "\tadd-repository - calls add-apt-repository within the chroot when available";
	echo "\thas-installed - checks if passed packages are installed on the system";
	echo "\texec - a utility for calling commands that would otherwise break when installed";
	echo "\t       by this script. It runs the passed command fully in the chroot.";
	echo "\t       can optionally be passed \`-g\` which will instead make it";
	echo "\t       attempt to call commands on the host system, without any PATH";
	echo "\t       modifications made by \`apt-local.sh export-paths\`."
	echo;
	echo "Additionally, this script supports a numerical log level scheme.";
	echo "To enable verbose script logging, set the VERBOSE environment";
	echo "variable to one of the following:";
	echo "\t0 = silent";
	echo "\t1 = error";
	echo "\t2 = warning";
	echo "\t3 = info";
	echo "\t4 = debug";
	echo "\t5+ = silly mode (controls extra verbose logging)";
	echo "NOTE: When VERBOSE is unset, the log level defaults to 2.";
	echo "      Also, this log level only applies to the script internals,";
	echo "      if you wish to silent the APT commands, you'll need to pass";
	echo "      the appropriate flags. See 'man apt' and 'man apt-get'.";
	echo;
	echo "See apt(8) for more information about the available commands.";
	;;
	*) # everything else throws an error to the user.
		echo "'$COMMAND' is not an appropriate command for this script.";
		echo "See 'apt-local --help' for a list of appropriate commands."
		return 1;
	;;
esac;

exit $RETURN;

# NOTE: should be called on exit anyway
#cleanup;
