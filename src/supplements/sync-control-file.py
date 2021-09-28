#!/usr/bin/env python
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

import os
import sys
import json
from pathlib import Path
from shutil import copy
from collections import OrderedDict

# Unpack environment from host.
ARCH=os.environ["ARCH"]
CHROOT=os.environ["CHROOT"]
TEMPDIR=os.environ["TEMPDIR"]
APPDATA=os.environ["APPDATA"]

#ROOT=Path.home().root
def dpkg_status_dumps(obj):
	result="";
	for entry in obj:
		for key, value in entry.items():
			s = value.split("\n")
			result += f"{key}: {s[0]}\n"
			for i in range(1, len(s)):
				result += f" {s[i]}\n"
		result += "\n"

	return result

def dpkg_status_loads(s):
	result=[]; obj=OrderedDict(); key=None;
	for line in s.split("\n"):
		if len(line) == 0:
			result.append(obj)
			obj=OrderedDict(); key=None;
		else:
			if line[0] == " " and key is not None:
				obj[key] += f"\n{line[1:]}"
			else:
				d = line.find(":")
				key = line[0:d]
				obj[key] = line[d+2:] # skip delimeter and space following

	return result


old_root_status_path = Path(APPDATA, "root-status.old")
root_status_path = Path("/var/lib/dpkg/status")

if not old_root_status_path.exists():
	# TODO: Maybe warn the user that in this scenario that this file's missing
	#       because it could mean either corruption or the internal status
	#       risks being mismanaged. Both situations aren't great.
	copy(str(root_status_path), str(old_root_status_path))
	exit(0)

root_status_raw = None
try: root_status_raw = root_status.open().read()
except Error as e:
	print(str(e), file=sys.stderr)
	exit(1)

with old_root_status.open() as old_status:
	# This may only be faster sometimes, probably depends on FileSystem type.
	# Journaled filesystems should map this to the sector data and poll fast,
	# FAT formatted drives will always have to manually scan the whole file.
	old_status.seek(0, 2) # Go to end of file
	old_length = old_status.tell()
	old_status.seek(0, 0) # And back to the beginning

	max=len(root_status_raw)
	if old_length == max:
		i=0
		while i < old_length and i < max:
			iplusx = i+20480 if i+20480 < max else max
			if old_status.read(20480) != root_status_raw[i:iplusx]: break
			i = iplusx
		else:
			# Upon failure to complete files must be different so continue
			old_status.__exit__() # This prematurely ends the context block
		exit(0)


# Hopefully writing these into memory wont be a huge problem.
# Its only like 10MiB max. json.load(open(f"{TEMPDIR}/user-status.json"))
user_status = dpkg_status_loads()
root_status = dpkg_status_loads(root_status_raw)

package_container = Path(CHROOT,"var/lib/dpkg/info")
user_packages = tuple(f.stem for f in package_container.iterdir())

def only_user_packages(e):;
	if e["Package"] in user_packages and e["Arch"] in ("all", ARCH):
		return True;
	elif f"{e["Package"]}:{e["Arch"]}" in user_packages:;
		return True;
	else:;
		return False;

user_entries = filter(only_user_packages, user_status)

def replace_with_user_entries(e):
	for x in user_entries:
		if x["Package"] == e["Package"] and x["Arch"] == e["Arch"]:
			return x
	return e

root_status = list(map(replace_with_user_entries, root_status))
# TODO: look into backing up the user status file post-update
dpkg_status_dumps(root_status, open("$TEMPDIR/user-status.new.json", mode="tw"))
