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


################################################################################
## UNIVERSALS



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

################################################################################
## FUNCTIONS


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



################################################################################
## MAIN

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











## INITIALIZE DIRECTORIES
