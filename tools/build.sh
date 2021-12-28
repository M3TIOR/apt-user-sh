#!/bin/sh
# @file - build.sh
# @brief - Shared functions for the apt-user.sh suite.
# @copyright - (C) 2021  Ruby Allison Rose
# SPDX-License-Identifier: MIT

### Linter Directives ###
# shellcheck shell=sh

################################################################################
## Globals (Comprehensive)

# Symlink script resolution via coreutils (exists on 95+% of linux systems.)
SELF=$(readlink -n -f "$0");
PROCDIR="$(dirname "$SELF")";
APPNAME="$(basename "$SELF")";
TMP="${XDG_RUNTIME_DIR:-/tmp}";
PATH="$PROCDIR/.bin:$PATH";

VERSION='';

BUILD_DEB="true";
BUILD_SIGNED="true";
BUILD_RELEASE="false";

RESET_TARGETS="true";
TARGETS="deb:ubuntu"; # TODO: deb:debian deb:linuxmint
################################################################################
## Imports

################################################################################
## Functions

reset_targets() {
	if $RESET_TARGETS; then
		TARGETS="";
		RESET_TARGETS="false";
	fi;
}

# @describe - Tokenizes a string into semver segments, or throws an error.
tokenize_semver_string(){
	s="$1"; l=0; major='0'; minor='0'; patch='0'; prerelease=''; buildmetadata='';

	# Check for build metadata or prerelease
	f="${s%%[\-+]*}"; b="${s#*[\-+]}";
	if test -z "$f"; then
		echo "\"$1\" is not a Semantic Version." >&2; return 2;
	fi;
	OIFS="$IFS"; IFS=".";
	for ns in $f; do
		# Can't have empty fields, zero prefixes or contain non-numbers.
		if test -z "$ns" -o "$ns" != "${ns#0[0-9]}" -o "$ns" != "${ns#*[!0-9]}"; then
			echo "\"$1\" is not a Semantic Version." >&2; return 2;
		fi;

		case "$l" in
			'0') major="$ns";; '1') minor="$ns";; '2') patch="$ns";;
			*) echo "\"$1\" is not a Semantic Version." >&2; return 2;;
		esac;
		l=$(( l + 1 ));
	done;
	IFS="$OIFS";

	# Determine what character was used, metadata or prerelease.
	if test "$f-$b" = "$s"; then
		# if it was for the prerelease, check for the final build metadata.
		s="$b"; f="${s%%+*}"; b="${s#*+}";

		prerelease="$f";
		if test "$f" != "$b"; then buildmetadata="$b"; fi;

	elif test "$f+$b" = "$s"; then
		# If metadata, we're done processing.
		buildmetadata="$b";
	fi;

	OIFS="$IFS"; IFS=".";
	# prereleases and build metadata can have any number of letter fields,
	# alphanum, and numeric fields separated by dots.
	# Also protect buildmetadata and prerelease from special chars.
	for s in $prerelease; do
		case "$s" in
			# Leading zeros is bad juju
			''|0*[!1-9a-zA-Z-]*|*[!0-9a-zA-Z-]*)
				echo "\"$1\" is not a Semantic Version." >&2;
			IFS="$OIFS"; return 2;;
		esac;
	done;
	for s in $buildmetadata; do
		case "$s" in
			''|*[!0-9a-zA-Z-]*)
				echo "\"$1\" is not a Semantic Version." >&2;
			IFS="$OIFS"; return 2;;
		esac;
	done;
	IFS="$OIFS";
}

git_tag_version() {
	if ! s="$(git describe --tag --long)"; then
		return 1;
	else
		OIFS="$IFS"; IFS="-"; set "$s"; IFS="$OIFS";
		eval "buildhash=\"\$$(($#))\"";
		eval "commitsahead=\"\$$(($# - 1))\"";
		tagversion="${@%-${commitsahead}-${buildhash}}";
	fi;
}

generate_build_version() {
	if ! git_tag_version; then
		if ! VERSION="$(git rev-parse --short HEAD)"; then
			VERSION="unknown";
		fi;
		VERSION="0.0.0+dev.unknown.$VERSION";
		return 0;
	fi;
	tokenize_semver_string "${tagversion#v}";
	if $BUILD_RELEASE; then
		if test -z "$VERSION"; then
			# Auto inc patch version if we haven't manually added a release version.
			VERSION="$major.$minor.$((patch + 1))";
			if test -n "$prerelease"; then
				VERSION="${VERSION}-$prerelease";
			fi;
		fi;
	else
		if test "$commitsahead" -gt 0; then
			# Empart a reasonable degree of precedence to the version. dev < rc
			VERSION="$major.$minor.$((patch + 1))-dev.$commitsahead.$buildhash";
			return 0;
		else
			# If we aren't any commits ahead of the last tag, we can assume we're
			# building a stable release.
			VERSION="${tagversion#v}";
		fi;
	fi;
}

build_package()
(
	FORMAT="$1";
	DISTRO="$2";
	DISTRO_VERSION="$3";

	PACKAGE="$(jq -r ".package" "$PROCDIR/build-conf.json")";

	case "$FORMAT" in
		'deb')
			echo "Building \".deb\" package for \"$DISTRO\"";

			get_distro() { cat "$PROCDIR/build-conf.json" | jq -cM ".debconf[] | select(.distro==\"$DISTRO\")"; };
			get_version() { get_distro | jq -cM ".version[] | select(.name==\"$DISTRO_VERSION\" // .codename==\"$DISTRO_VERSION\")"; };

			DEB_ROOT="$TEMPDIR/${PACKAGE}_${VERSION}_all";
			CONTROL_ROOT="$DEB_ROOT/DEBIAN";

			# Make sure all our parent paths exist.
			mkdir -p "$CONTROL_ROOT";

			{
				echo "Package: $PACKAGE";
				echo "Version: $VERSION";
				echo 'Architecture: all';
				echo 'Essential: no';
				echo "Priority: optional";

				echo "Depends: $(get_version | jq -r '.dependencies | join(", ")')";

				echo "Maintainer: $MAINTAINER";
				echo "Description: $(
					jq -r '.description | join(" ")' "$PROCDIR/build-conf.json"
				)";
			} >> "$CONTROL_ROOT/control";

			type get_distro;
			type get_version;

			# NOTE: Can I just say, this security model fucking sucks. WTF were the
			#       Debian devs thinking? Let's just get this done? Whyyyyyyyyyy
			#       Ah yes, let's just trust every package to be safe,
			#       there aren't any mallicious people on the web. It's fiiiiiiine.
			parse_controlfile() {
				case "$(get_version | jq -r ".$1 | type")" in
					"string") get_version | jq -r ".$1" >> "$CONTROL_ROOT/$1";;
					"array") get_version | jq -r ".$1 | join(\"\n\")" >> "$CONTROL_ROOT/$1";;
					*)
						case "$(get_distro | jq -r ".$1 | type" )" in
							"string") get_distro | jq -r ".$1" >> "$CONTROL_ROOT/$1";;
							"array") get_distro | jq -r ".$1 | join(\"\n\")" >> "$CONTROL_ROOT/$1";;
						esac;
					;;
				esac;
				if test -e "$CONTROL_ROOT/$1"; then
					chmod 755 "$CONTROL_ROOT/$1";
				fi;
			}

			parse_controlfile "preinst";
			parse_controlfile "postinst";
			parse_controlfile "prerm";
			parse_controlfile "postrm";

			#mkdir -p "${DEB_ROOT}/usr/local/bin";
			mkdir -p "${DEB_ROOT}/usr/share/$PACKAGE";
			cp -a -t "${DEB_ROOT}/usr/share/$PACKAGE" "$PROCDIR/../src/"*;

			dpkg-deb \
				--build "$DEB_ROOT" \
				"$PROCDIR/../build/${PACKAGE}_v${VERSION}_${DISTRO}.deb";
		;;
	esac;
)

################################################################################
## Main Script

if ! type jq 1>/dev/null; then
	# The only package that needs to be latest is shellcheck because it provides
	# protection of our sourcecode. As much as I'd like to have both sources
	# hash validated to eliminate the MiM risk vector, I can't for all systems.
	# Neither package author provides checksums.
	echo "Fetching jq...";
	curl -L --progress-bar \
		-o "$PROCDIR/.bin/jq" \
		"https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64";

	chmod +x "$PROCDIR/.bin/jq";
fi;

while test "$#" -gt 0; do
	case "$1" in
		-h|--help)
			echo 'Usage: build.sh [-hum] [-r [VERSION]] [-t "FORMAT:DISTRO[:VERSION]" [-t ...]]';
			echo;
			echo "Copyright: (C) 2021  Ruby Allison Rose";
			echo "This program comes with ABSOLUTELY NO WARRANTY! This is free software,";
			echo "and you are welcome to redistribute it under certain conditions.";
			echo "For more information see https://spdx.org/licenses/MIT.html";
			echo;
			echo 'Description:';
			echo '\tBuild automation for notify-send-sh. By default builds all';
			echo '\tpackages for all distros. When a single option is specified,';
			echo '\tit only builds the specified target instead.';
			echo '';
			echo 'Help Options:';
			echo '\t-h|--help            Show help options.';
			echo '';
			echo 'Application Options:';
			echo "\t-m  --maintainer[=...]  Name of the maintainer for this build";
			echo "\t-u, --unsigned          Don't create hash checksums.";
			echo "\t-r, --release[=...]     Publish a new git release.";
			echo "\t-t, --target[=...]      Only build specific target distro in format";
			echo "\t    --list-targets      Print available targets";
			echo "\t    --list-formats      Print available formats";
			exit;
		;;
		-u|--unsigned) BUILD_SIGNED="false";;
		-r|--release|--release=*)
			if test "$1" != "${1#--release=}"; then s="${1#*=}";
				s="${s#v}";
				if ! tokenize_semver_string "$s"; then exit 1; fi;
				VERSION="$s";
			fi;
			BUILD_RELEASE='true';
		;;
		-t|--target|--target=*)
			if test "$1" != "${1#--target=}"; then s="${1#*=}"; else shift; s="$1"; fi;
			reset_targets;
			TARGETS="$TARGETS $s";
		;;
		-m|--maintainer|--maintainer=*)
			if test "$1" != "${1#--maintainer=}"; then s="${1#*=}"; else shift; s="$1"; fi;
			MAINTAINER="$s";
		;;
		--list-targets)
			echo "Supported Targets:";
			jq '.debconf[].distro' "$PROCDIR/build-conf.json";
			exit;
		;;
		--list-formats)
			echo "Supported Formats:";
			echo "\tdeb";
			# TODO:
			#echo "\trpm";
			exit;
		;;
	esac;
	shift;
done;

# Fetch maintainer from git if it's not specified by CLI. Fail if we don't
# know them. The maintainer is crucial for ensuring people know who's resposible
# for a package, especially when it's misbehaving.
if test -z "$MAINTAINER" && ! MAINTAINER="$(git config --get user.name)"; then
	echo "Error: couldn't determine this build's maintainer using" >&2;
	echo "       'git config', please build again using the '-m' option." >&2;
fi;

generate_build_version;
rm -rf "$PROCDIR/../build";
mkdir -p "$PROCDIR/../build"; # We want our build files to appear in the repo root.
TEMPDIR="$(mktemp -p "$TMP" -d "notify-send-sh_build.XXX")";
trap "rm -rvf $TEMPDIR" 0;

for format_distro in $TARGETS; do
	build_package $(IFS=":"; echo $format_distro);
done;

# Hash generation and signing
# https://www.gnupg.org/gph/en/manual/x135.html
if $BUILD_SIGNED; then
	for file in "$PROCDIR/../build/"*; do
		sha256sum "$file" >> "$PROCDIR/../build/sums.sha256";
	done;

	gpg --detach-sign "$PROCDIR/../build/sums.sha256";
fi;
