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
## MAIN


# TODO: implement lock waiting of user stores before execution of
