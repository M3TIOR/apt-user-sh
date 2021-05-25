#!/bin/sh -e
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
# NOTE: There may be issues with using a dedicated UnionFS FUSE, because each
#       process has a FD cap. Quoted from the `unionfs-fuse` manpages:
#         Most system have a default of 1024 open files per process.
#         For example if unionfs-fuse servs "/" applications like KDE or GNOME
#         might have much more open files, which will make the unionfs-fuse
#         process to exceed this limit.
#         Suggested for "/" is >16000 or even >32000 files.
#

# Get process directory
a="/`readlink -f $0`"; a=${a%/*}; a=${a#/}; a=${a:-.}; PROCDIR=$(cd "$a"; pwd);

. $PROCDIR/common.sh;

# Parse the system PATH and only modify that. Leaves unnecessary user dirs.
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
done < /etc/environment;

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
