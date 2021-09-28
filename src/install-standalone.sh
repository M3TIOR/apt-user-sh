# shellcheck shell=sh
# @file - common.setup.sh
# @brief - Shared setup code for the notify-send.sh suite.
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
## Globals


################################################################################
## Functions

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

	mkdir -p $TEMPDIR/downloads;

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

################################################################################
## Main Script

# TODO: Run from unpacked .deb; move files into the standalone directory,
#       link to the user bin directory, and install dependency packages parsed
#       from the .deb CONTROL file since different distro's packages differ.
#
#       You hear me; me? Treat all the dependencies as if they exist already
#       in every other file!

# TODO: install apt-user depedencies if we're in standalone mode.

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

MISSING_DEPENDS=`list_missing_fixable_dependencies`;
if test -n "$MISSING_DEPENDS"; then
	install_dependencies $MISSING_DEPENDS;
fi;
