#!/bin/sh -e
# NOTE; This script is not intended to be sourced.
################################################################################
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
TMPDIR="${XDG_RUNTIME_DIR:-/tmp}";
TEMPDIR="$(mktemp -p "$TMPDIR" -d apt-local-unionfs-XXXXXXXXX)";
VERBOSE=${VERBOSE-2}; # NOTE: this is assinging a default of 2, not subtracting.

################################################################################
## Functions

# XXX: setup MUST come before functions, otherwise stderr and stdout get all screwy.
. "$PROCDIR/apt-user.shared.d/setup.sh"; # Ensures we have debug and logfile stuff together.
. "$PROCDIR/apt-user.shared.d/functions.sh"; # Import shared code.

################################################################################
## Main Script

# TODO: implement synchronization of different user stores with the root store
#       to be run after dpkg finishes installing packages.
