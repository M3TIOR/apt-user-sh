#!/bin/sh
# @file - notify-send.sh
# @brief - drop-in replacement for notify-send with more features
# NOTE: Needs `chmod u+x` to function properly.
# NOTE; This script is not intended to be sourced.
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

SELF=$(readlink -n -f "$0");
PROCDIR="$(dirname "$SELF")";
APPNAME="$(basename "$SELF")";
TMP="${XDG_RUNTIME_DIR:-/tmp}";
TEMPDIR="$(mktemp -p "$TMP" -d apt-user.XXXXXXXXX)";
VERBOSE=${VERBOSE-2}; # NOTE: this is assinging a default of 2, not subtracting.

################################################################################
## Functions

. "$PROCDIR/apt-user.shared.d/setup.sh"; # Ensures we have debug and logfile stuff together.
. "$PROCDIR/apt-user.shared.d/functions.sh"; # Import shared code.


# NOTE: should always run upon exit because we have a temp dir to clean up.
cleanup() {
	# Make sure the unionfs is down, then remove the container.
	info "Running cleanup script...";
	rm -rf "$TEMPDIR";
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
containerize()
(
	OPTARG='';
	OPTIND=0;

	while getopts R option; do
		case "$option" in
			R) FAKE_ROOT="-0";;
		esac;
	done;

	# clear getopts parsed args so we can access positional args by index.
	shift $(($OPTIND-1));

	# NOTE: proot verbosity should be included in Silly Mode.
	# XXX: Unfortunately apt and apt-get force require root for installing
	#      packages. I wanted this to be done without even faking root,
	#      so there wouldn't be any issues with file permissions down the road.
	proot \
			-b "/etc/host.conf" \
			-b "/etc/hosts" \
			-b "/etc/nsswitch.conf" \
			-b "/dev/" \
			-b "/sys/" \
			-b "/proc/" \
			-b "/tmp/" \
			-b "$HOME" \
			$FAKE_ROOT -r $MOUNT $*;
)

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

list_packages() {
	# NOTE: '/var/lib/dpkg/info/' holds information files for all installed
	#       debian packages. Files are stored with names matching the binary
	#       package name searchable in apt, and have suffixes for their
	#       function. '[package].list' files contain a log of all the files
	#       modified / installed by the package. If it exists, the package
	#       should be installed.
	case $1 in
		"installed") shift;
			for p in $*; do
				if ! -e "$CHROOT/var/lib/dpkg/info/$p.list"; then
					echo "$p";
				fi;
			done;
		;;
		"uninstalled") shift;
			for p in $*; do
				if -e "$CHROOT/var/lib/dpkg/info/$p.list"; then
					echo "$p";
				fi;
			done;
		;;
		*)
			return 2;
		;;
	esac;
}

packages_for() {
	# This invokes a subshell anyway, so don't need to pad the outside with one.
	# Holy $H!T doing a loop of `dpkg -S` invocations cost 0.33 seconds of init
	# time for ever itteration. Glad this is faster.
	{
		while test "${#}" -gt 0; do
			find "$1" -follow ! -type d -print; shift;
		done;
	} | \
	xargs dpkg -S 2>/dev/null | \
	grep -P -o '.*(?=:)' | \
	sort -u -;
}

is_unlocked()
(
	# NOTE: lslocks is the only good candidate for this, because it can print
	#       root locks from an unprivleged state. We have to guarantee there's
	#       as little faking root as possible. IMHO doing that is a security flaw.
	lslocks -rn --output COMMAND,PID | grep 'apt' | \
	{
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

		done;
	}
	wait "$LOCKPID";
)

is_unionfs_mounted(){
	# XXX: There's no way I can guarantee that each system will implement the fs
	#      type name, the same way, so I used multiple `-t type` options as an
	#      attempt to cover all possibilities. But that may create a BUG l8r.
	df \
		-t fuse.unionfs-fuse \
		-t fuse.unionfs \
		-t fuse \
		"$MOUNT" 1>/dev/null 2>/dev/null;
}

dpkg_status_to_json() {
	printf "{";
	sed -zE \
		-e 's/"/\\"/g' \
		-e 's/\n / /g' \
		-e 's/([a-zA-Z\-]+): ([^\n]+)\n/"\1":"\2",/g' \
		-e 's/,\n/\}\{/g' \
		"$1";

	# TODO: possiblly truncate empty object at the end of this.
	#       status file should always end in two newlines so "},{" must be
	#       dealt with somehow.
	printf "}";
}

sync_control_file() {
	# NOTE: unfortuantely, dpkg uses a single control file scheme, which is
	#       incompatable with automatic updates from the unionfs. This implements
	#       an update system. It pulls all changes from the system admin control
	#       file into the user control file without overwriting user managed
	#       package metadata.

	ARCH="$(dpkg-architecture -q DEB_HOST_ARCH)" \
	TEMPDIR="$TEMPDIR" \
	CHROOT="$CHROOT" \
	APPDATA="$APPDATA" \
	python "$PROCDIR/supplements/sync-control-file.py"

	# Only updates the control file if there have been changes made by root.
	if test -e "$APPDATA/root-status.old" \
	   && diff "$APPDATA/root-status.old" \
	           /var/lib/dpkg/status 1>/dev/null 2>/dev/null;
	then
		return 0;
	fi;

	# NOTE: this tries to reduce the window of time which this function is
	#       vulnerable to race conditions introduced by the root package store.
	cp /var/lib/dpkg/status "$TEMPDIR/root-status";
	dpkg_status_to_json "$TEMPDIR/root-status" > "$TEMPDIR/root-status.json";
	dpkg_status_to_json "$CHROOT/var/lib/dpkg/status" > "$TEMPDIR/user-status.json";

	# First we have to find out what packages we actually have in the user store.
	# From there, we'll overwrite entries from the root status file using the user
	# entreis. Since the data within the user data store should always be current
	# we can assume that no other packages have changed since our last invocation.

	# TODO: introduce autoremove functionality to reduce bloat by checking for
	#       duplicated auto-installed packages between the user and root.

	# jq -Mr --slurpfile root ./test.json \
	# 	'if .[1] == "" then (.[0] as $pkgname | $root[0][] | until(.Package == $pkgname; empty) | [.Package, .Architecture]) else . end | tostring'
	# WTF `jq` why the hell is this slower? The code is shorter, so this should
	# be faster right? Perhaps it's something to do with `jq`'s itteration
	# algorithm. May just be slower because it's interpreted more times?
	# Or it could also be that I'm an idiot and didn't remember that
	# each pipe conditional acts on every element of the array it's being passed.

	# At this point I'm worried about the speed impact, JQ adds a lot to the
	# execution time depending on the number of packages in our store.
	# My root store took ~5.5s to process. That's pretty SLOOOOOOOWWWWW.

	# # So slurp up everything.
	# basename -a -s '.list' "$CHROOT/var/lib/dpkg/info/"*.list \
	# 	| sed -E -e 's/(.+):(.+)|(.+)/["\1\3","\2"]/' \
	# 		| jq -Mr \
	# 			--slurpfile user "$TEMPDIR/user-status.json" \
	# 			--slurpfile root "$TEMPDIR/root-status.json" \
	# 			"$(printf '%s %s %s %s %s %s %s %s %s' \
	# 				'. as $pkg |' \
	# 				'$root[] |'
	# 					'select(.Package == $pkg[0]' \
	# 					'and' \
	# 					'any(.Architecture | inside([$pkg[1], "any",' \
	# 					"\"$(dpkg-architecture -q DEB_HOST_ARCH)\"" \
	# 				']))) |' \
	# 				'if .Package == $pkgname then . else empty end else . end |'
	# 				'$root[] | select($[]))' \
	# 			)";

	# TBH I really don't want to include python because it's pretty big
	# comparatively speaking, and it's on fewer systems. But unfortunately
	# JQ seems to be a real piece of work and this is the fastest solution
	# I have for now.
	{
		ARCH="$(dpkg-architecture -q DEB_HOST_ARCH)";
		#printf "%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s"
		# Could make this even faster by removing the multiple echos and using
		# a single printf, but that would look like garbage and I want this to be
		# at least somewhat maintainable.
		echo 'import json;';
		echo 'from pathlib import Path';
		echo # Hopefully writing these into memory won't be a huge problem.
		echo # It's only like 10MiB max.
		echo "user_status = json.load(open(\"$TEMPDIR/user-status.json\"))";
		echo "root_status = json.load(open(\"$TEMPDIR/root-status.json\"))";
		echo 'root_status.pop(); user_status.pop()'; # sanitize garbage objects.
		echo
		echo "user_packages = tuple(f.stem for f in Path(\"$CHROOT/var/lib/dpkg/info/\").iterdir())";
		echo
		echo 'def only_user_packages(e):';
		echo "	if e[\"Package\"] in user_packages and e[\"Arch\"] in (\"all\", \"$ARCH\"):";
		echo '		return True';
		echo '	elif f"{e["Package"]}:{e["Arch"]}" in user_packages:';
		echo '		return True';
		echo '	else:';
		echo '		return False';
		echo
		echo 'user_entries = filter(only_user_packages, user_status)';
		echo
		echo 'def replace_with_user_entries(e):';
		echo '	for x in user_entries';
		echo '		if x["Package"] == e["Package"] and x["Arch"] == e["Arch"]:';
		echo '			return x';
		echo '	return e';
		echo
		echo 'root_status = list(map(replace_with_user_entries, root_status))';
		echo "json.dump(root_status, open(\"$TEMPDIR/user-status.new.json\",mode=\"tw\"))"
	} | python -;

	# rm $APPDATA/status.json;
	# touch $APPDATA/status.json;



	# # The current algorithm will use a two pass system. It's very inefficient.
	# # TODO: Make this faster.
	# OIFS="$IFS"; IFS="";
	# while read LINE; do
	# 	IFS="$OIFS";
	# 	if test -n "$SKIP"; then
	# 		if test -z "$LINE"; then
	# 			SKIP="";
	# 			# Ensure replacement of newline into control file.
	# 			echo >> $APPLICATION_DATA/dpkg-status;
	# 		fi;
	# 	elif starts_with "$LINE" "Package: " &&
	# 	   test -e "$USER_CONTAINER/var/lib/dpkg/info/${LINE#Package: }.list"; then
	# 		# This first pass should concatenate all system packages not in the chroot
	# 		# to the intermediary file.
	# 		SKIP="1";
	# 	else
	# 		# Append lines into the intermediary file.
	# 		echo -- "$LINE" >> $APPLICATION_DATA/dpkg-status;
	# 	fi;
	# 	IFS=""; # reset IFS before next `read` cycle
	# done < $TEMPDIR/dpkg-system-status.new;
	#
	# while read LINE; do
	# 	IFS="$OIFS";
	#
	# 	if test -n "$SKIP"; then
	# 		if test -z "$LINE"; then
	# 			SKIP="";
	# 			printf "\n" >> $APPLICATION_DATA/dpkg-status;
	# 		fi;
	# 	elif starts_with "$LINE" "Package: " &&
	# 	     test ! -e "$USER_CONTAINER/var/lib/dpkg/info/${LINE#Package: }.list"; then
	# 		# This second pass should push all local package metadata down into the
	# 		# intermediary file.
	# 		SKIP="1";
	# 	else
	# 		printf "$LINE\n" >> $APPLICATION_DATA/dpkg-status;
	# 	fi;
	#
	# 	IFS="";
	# done < $USER_CONTAINER/var/lib/dpkg/status;
	# IFS="$OIFS";
	#
	# # Migrate the new status file to the old one.
	# cp -u $TEMPDIR/root-status.new $APPDATA/root-status.old;
	#
	# # Then, finally we need to copy over the intermediary into the user container
	# # so the contained dpkg and apt suite can see the system package changes and
	# # accomidate for them.
	# cp -u $APPLICATION_DATA/dpkg-status $USER_CONTAINER/var/lib/dpkg/status;
	#
	# return 0;
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
	{
		packages_for /vmlinuz /sbin/init /usr/sbin/grub;

		# TODO: Also hold packages that apt-user depends on if installed in
		#       standalone mode. Should check for file presented by standalone.sh
		if test -e "$APPDATA"; then
			true;
		fi;
	} \
	| xargs apt-mark hold $STAGED >&6;
}

print_help(){
	echo "Usage: apt-user [-hV] [-v [NUM]] [-U] APT_COMMAND [APTARGS...]";
	echo;
	echo "Description:";
	echo "\t'apt-local' is a script that provides APT features in a multi-user environment";
	echo "\tfriendly way. It creates user specific packages and apt caches using a unionfs";
	echo "\tchroot, and provides the same functionality as specialized APT tools.";
	echo;
	echo "Help Options:";
	echo "\t-h            - Prints this help text.";
	echo "\t-V, --version - Prints the version of this script.";
	echo;
	echo "Arguments:";
	echo "\t-v, --verbose - Changes the verbosity of this script.";
	echo "\t                This script supports a numerical log level scheme.";
	echo "\t                0 = silent, 1 = error, 2 = warning, 3 = info, 4 = debug,";
	echo "\t                5+ = silly mode (controls extra verbose logging)";
	echo "\t                NOTE: When VERBOSE is unset, the log level defaults";
	echo "\t                      to 2. Also, this log level only applies to";
	echo "\t                      the script internals, if you wish to silent";
	echo "\t                      the APT commands, you'll need to pass";
	echo "\t                      the appropriate flags. See 'man apt'.";
	echo;
	echo "APT_COMMANDs:";
	# NOTE: Use escape sequence instead of inline tabs because it's explicit
	#       Not everyone uses an editor that shows them whitespace characters.
	echo "\tlist           - list packages based on package names";
	echo "\tsearch         - search in package descriptions";
	echo "\tshow           - show package details";
	echo "\tinstall        - install packages";
	echo "\tremove         - remove packages";
	echo "\tpurge          - remove packages and configuration data";
	echo "\tautoremove     - Remove automatically all unused packages";
	echo "\tupdate         - update list of available packages";
	echo "\tupgrade        - upgrade the system by installing/upgrading packages";
	echo "\tfull-upgrade   - upgrade the system by removing/installing/upgrading";
	echo "\tedit-sources   - edit the source information file";
	echo;
	echo "QOL APT_COMMANDs added by yours truely:";
	echo "\tadd-repository - calls add-apt-repository for this user";
	echo "\thas-installed  - checks if passed packages are installed on the system";
	echo;
	echo "See apt(8) for more information about the available commands.";
}

################################################################################
## Main Script


# Process initial flag modifiers
POSTPROC_ARGS="";
while test "${#}" -gt 0; do
	case "$1" in
		-h|--help) print_help; exit;;
		-V|--version) printf '%s\n' "v$VERSION"; exit;;
		-v|--verbose)
			if "$(typeof -g "$2")" -gt 1; then
				abrt "verbose flag expected integer, got "$2" which is '$(typeof "$2")'";
			fi;
			VERBOSE="$2"; shift;
		;;
		*) POSTPROC_ARGS="$POSTPROC_ARGS \"$(sanitize_quote_escapes "$1")\"";;
	esac;
	shift;
done;
eval "set $POSTPROC_ARGS";
COMMAND="$1"; shift;

trap "cleanup" 0; # Always cleans up except when KILLed

exec 3>&2; exec 4>&2; exec 5>&2; exec 6>&2;
for FD in `seq 6 -1 $((VERBOSE+3))`; do
	# TODO: see if this can be done without eval;
	#       It's just better when thing's don't use eval;
	eval "exec $FD>/dev/null";
done;

alias proot="pseudochroot -i $CHROOT proot -v $((VERBOSE-5))";
alias lslocks="pseudochroot -i $CHROOT lslocks";
alias apt-mark="containerize -R apt-mark";
alias apt-mark="containerize -R apt-cache";
# NOTE: adjusts apt-get to supress Autoremove warnings.
# TODO: implement local AUTOREMOVE eligibility notification.
alias apt-get="containerize -R apt-get -o APT::Get::HideAutoRemove=1";

# Executes at debug verbosity.
if test $VERBOSE -gt 3; then
	# Should make every "busybox" and "coreutils" command verbose when ran.
	alias rm="rm -v";
	alias cp="cp -v";
	alias mkdir="mkdir -v";
	alias readlink="readlink -v";

	# OLDFLAGS
	#BVF="-v";
	#USV="-d -o debug";
fi;

# Silly verbosity
if test $VERBOSE -gt 4; then
	PS4="\$SELF in PID#\$\$ @\$LINENO: ";
	set -x;
	trap "set >&6;" 0;
fi;


if ! type add-apt-repository >&6; then
	info "Info: Missing optional, the 'add-repository' command will be disabled.";
fi;

if ! UID="$(id -u)"; then
	error "Error: Failed to fetch UID of caller.";
	error "       Running 'chmod u+x {this_script}' should fix this.";
fi;


mkdir -p $APPDATA;
mkdir -p $CHROOT;
mkfifo $TEMPDIR/fifo1;
mkfifo $TEMPDIR/fifo2;

if ! is_unlocked; then
	error "You're already running an instanced of apt-user, or your" \
	      "sysadmin is running an apt command and the root is locked." \
	      "Try again later when that has finished.";
	exit 100;
fi;

warning "Syncing 'dpkg' control files.";
if sync_control_file; then
	warning "Updating held packages.";
	if ! update_held_packages; then
		warning "Couldn't update held packages; it's inadvisable to run" \
		        "'apt-local full-upgrade' in this state. For more info" \
		        "see 'VERBOSE=4 apt-local ...'";

		if test "$COMMAND" = "full-upgrade"; then
			echo "Are you sure you want to run 'full-upgrade' in this state?";
			echo "This will probably always cause unnecessary bloat.";
			if ! query_yn; then
				exit 100;
			fi;
		fi;
	fi;
fi;

warning "Checking for broken packages introduced by the sysadmin...";
apt-get install -q --fix-broken --yes >&5;
if ! test "$?" -eq 0; then
	error "Couldn't fix broken packages, run 'VERBOSE=4 apt-local ...'" \
	      "for more information and consider submitting a bug report.";
fi;

case "$COMMAND" in
	# TODO: if I can't only list packages with updates from the user container,
	#       then don't list any at all.
	'list') dpkg-query --list $*;;
	'search') apt-cache search $*;;
	'show') apt-cache show $*;;
	'upgrade') apt-get upgrade $*;;
	'clean'|'update') apt-get $COMMAND $*;;
	'install')
		# NOTE: I want users to be able to install newer packages over
		#       unmaintained system packages / copy existing packages installed
		#       in the system to their own container, for version isolation when
		#       desired. --reinstall should allow package isolation,
		apt-get install $*;

		# TODO: check packages for external resources, and  add them to a list
		#       for which the binaries will be managed with update-alternatives
		#       so they can automatically be run within the chroot.
		#       This will remove the need to have the exec function at all
		#       and reduce the need for advanced user intervention.
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

		apt-get upgrade $PACKAGES $*;
	;;
	'purge'|'remove')
		# TODO: Only remove packages installed within the user chroot
		if sanitize_aptget $*; then
			if packages_are installed $RETURN2; then
				apt-get "$COMMAND" $*;
			else
				error "Couldn't find the following packages installed in the" \
				      "user container -> $RETURN1";
			fi;
		else
			apt-get "$COMMAND" $*;
		fi;
	;;
	'autoremove')
		# TODO: don't actually call `autoremove`; use conditional `remove`
		#       to only remove packages installed within the chroot
		#       DO use `autoremove` as a resolver to find which packages are
		#       eligable for removal.
		#
		# NOTE: There's technically a new type of autoremove eligable file here
		#       when the user has a duplicate package installed in auto mode
		#       that's also installed by the host.
		apt-get autoremove $*;
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

	# TODO: maybe add user update-alternatives functionality to improve binary compat.

	'has-installed')
		# TODO: test automate check all packages in argument list.
		# NOTE: this is currently unfinished, it doesn't yet exclude system packages.
		if ! packages_are installed $@; then
			printf "%s\n" "$RETURN2";
		else
			exit 0;
		fi;
	;;
	*) # everything else throws an error to the user.
		error "'$COMMAND' is not an appropriate command for this script." \
		      "See 'apt-local --help' for a list of appropriate commands."
		return 1;
	;;
esac;
