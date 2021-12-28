#!/bin/sh
# @file - sync-apt-user.sh
# @brief - When installed by a sysadmin, ensures apt-user won't break while
#          updating system packages. Packages must be installed one-at-a-time.
# @copyright - (C) 2021  Ruby Allison Rose
# SPDX-License-Identifier: GPL-3.0-only

### Linter Directives ###
# shellcheck shell=sh

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
