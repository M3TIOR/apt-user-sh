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


LOGFILE="${LOGFILE:-${XDG_RUNTIME_DIR:-/tmp}/.profile.$$.log}";

e553d8219517542a4dbbaee02757af2()
(
	#TEMPDIR="$(mktemp -p "$TMP" -d apt-user.enable.XXXXXXXXX)";
	VERBOSE=${VERBOSE:-2};

	################################################################################
	## Includes

	. "$PROCDIR/apt-user.shared.d/setup.sh";
	. "$PROCDIR/apt-user.shared.d/functions.sh";

	################################################################################
	## Functions

	ensure()
	(
		OPTARG=''; OPTIND=0;

		while getopts fv option; do
			case "$option" in
				'f') ENSURE_FILE=1;;
				'v') VERBOSE=1;;
			esac;
		done;

		shift "$(($OPTIND-1))";

		for ARG in $*; do
			if mkdir -p "${ARG%/*}" && ! test -e "$ENSURE_FILE"; then
				if touch "$ARG" && test -n "$VERBOSE"; then
					# Assume on error, touch or mkdir will throw an error for us.
					echo "created file '$ARG'";
				fi;
			fi;
		done;
	)

	################################################################################
	## Main Script

	# TODO: Implement as opt-in service instead of using the apt-user main script
	#       for everything. We can initialize the unionfs here and do pseudochroot
	#       path modifications to read the user environment. When this isn't
	#       sourced by .profile, apt-user will just instruct users to opt-in.
	#
	#       This allows us to have a single dedicated UnionFS FUSE per user
	#       that doesn't need to be initialized multiple times and impact
	#       performance across multiple calls to apt-user.
	#
	#       Program linkage can be handled selectively based on known compatability
	#       with the pseudochroot. Default linkage should enforce every user binary
	#       be started within proot for maximum compatability.
	#
	# REVISION:
	#       Actually, it would be better for compatability if each application was
	#       wrapped in a proot binder. The unionfs will still always need to be up.
	#

	alias unionfs-fuse="pseudochroot -i -a $APPDATA/fuse.pid $CHROOT unionfs-fuse";

	# Executes at debug verbosity.
	if test $VERBOSE -gt 3; then
		# Should make every "busybox" and "coreutils" command verbose when ran.
		alias rm="rm -v";
		alias cp="cp -v";
		alias mkdir="mkdir -v";
		alias readlink="readlink -v";
		# When debug verbosity, make sure unionfs is verbose too.
		alias unionfs-fuse="pseudochroot -i -a $APPDATA/fuse.pid $CHROOT unionfs-fuse -d -o debug";
	fi;

	if ! UID="$(id -u)"; then
		error "Failed to fetch UID of caller." \
					"Running 'chmod u+x {this_script}' should fix this.";
	fi;

	# Make sure we have a mountpoint to load up.
	mkdir -p "$MOUNT";

	if ! test -d "$CHROOT"; then
		info "Initializing new container...";
		mkdir -p "$CHROOT";

		# NOTE: should only make DPKG and the APT suite useable.
		ensure -f \
			"$CHROOT/var/lib/dpkg/lock" \
			"$CHROOT/var/lib/dpkg/lock-frontend" \
			"$CHROOT/var/lib/dpkg/triggers/Lock" \
			"$CHROOT/var/lib/apt/lists/lock" \
			"$CHROOT/var/cache/apt/lock" \
			"$CHROOT/var/cache/apt/archives/lock" \
			"$CHROOT/var/cache/debconf/passwords.dat";

		# NOTE: essential folders also need to be initialized, to correctly set
		#       the file ownership and privilage metadata.
		ensure \
			"$CHROOT/var/lib/apt/lists/partial" \
			"$CHROOT/var/cache/apt/archives/partial";
	fi;

	info "Starting UnionFS FUSE";
	unionfs-fuse \
		-o fsname=apt-local \
		-o auto_unmount \
		-o cow \
		-o max_files=16000 \
		-o big_writes \
		-o hard_remove \
		-f \
		"$CHROOT=RW:/=RO" \
		"$MOUNT";
)

ed37f8371f9acceef643f3a63a90193(){
	VERBOSE=${VERBOSE:-2};

	. "$PROCDIR/apt-user.shared.d/setup.sh";

	PATH="";
	while read line; do
		# The sysadmin shouldn't put a lowercase PATH in, because posix
		# environment variables are case sensitive.
		VAR=${line%=*}; if test "$VAR" = "PATH"; then
			line=${line#*=}; line=${line#\"}; line=${line%\"};
			OIFS="$IFS";
			IFS=":";
			for p in $line; do
				mkdir -p "$BINDIR/$p" >&2;
				PATH="$PATH:$BINDIR/$p";
			done;
			IFS="$OIFS";
			PATH=${PATH#:}; # Remove the prefix in a post process.
		fi;
	echo "$PATH";

	done < /etc/environment;
}

# Don't cluster user's .profile hashmap; everything is encapsulated
VERBOSE="$VERBOSE" LOGFILE="$LOGFILE" e553d8219517542a4dbbaee02757af2;
if test "$?" -eq 0; then
	export PATH="$(VERBOSE="$VERBOSE" LOGFILE="$LOGFILE" ed37f8371f9acceef643f3a63a90193):${PATH}";
fi;
unset ed37f8371f9acceef643f3a63a90193;
unset e553d8219517542a4dbbaee02757af2;
