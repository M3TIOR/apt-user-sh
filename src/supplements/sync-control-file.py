#!/usr/bin/env python
# @file - sync-control-file.py
# @brief - Synchronizes the user chroot dpkg status file with the system status.
# @copyright - (C) 2021  Ruby Allison Rose
# SPDX-License-Identifier: GPL-3.0-only

import os
import sys
import json
import pdb
from pathlib import Path
from shutil import copy
from collections import UserDict

# Unpack environment from host.
ARCH=os.environ["ARCH"]
CHROOT=os.environ["CHROOT"]
TEMPDIR=os.environ["TEMPDIR"]
APPDATA=os.environ["APPDATA"]

class OrderedDict(UserDict):
	def __repr__(self): return f"OrderedDict([{','.join(str(x) for x in self)}])"
	def __str__(self): return "{" + ",".join(f"\"{x[0]}\":{x[1]}" for x in self) + "}"
	def __len__(self): return len(values)

	def __init__(self, *kvp):
		self.values=[]
		self.data={}
		for i, (k, v) in enumerate(kvp):
			self.data[k] = i
			values.append(v)

	def __iter__(self):
		ordered = sorted(self.data.items(), key=lambda x: x[1])
		return iter((i[0], self.values[i[1]]) for i in ordered)

	def __getitem__(self, key):
		return self.values[self.data[key]]

	def __setitem__(self, key, value):
		if key in self.data:
			l = len(self.values)
			a = tuple(self.__iter__())
			i = self.data[key]

			# Shift values back
			self.values[i:l-1] = [p[1] for p in a[i+1:l]]

			# Shift keys back
			while i < l-1:
				self.data[a[i][0]] = self.data[a[i+1][0]]
				i+=1

			# Replace key value pair at end
			self.data[key] = l-1
			self.values[l-1] = value
		else:
			# When we can't find the key, the entry is new and we should extend
			# the list, otherwise we just increment the value mod counter,
			# update the value and location.
			self.data[key] = len(self.values)
			self.values.append(value)

	def __delitem__(self, key):
		l = len(self.values)
		i = self.data[key][1]
		if i == l-1:
			del self.data[key]
			self.values.pop()
		else:
			# Generate array first so we have the old values cached.
			a = tuple(self.__iter__())

			# Shift values back
			self.values[i:l-1] = [p[1] for p in a[i+1:l]]
			self.values.pop()

			# Shift keys back
			while i < l-1:
				self.data[a[i][0]] = self.data[a[i+1][0]]
				i+=1
			del self.data[key]


#ROOT=Path.home().root
def dpkg_status_dumps(obj):
	result="";
	for entry in obj:
		for key, value in entry:
			s = value.split("\n")
			result += f"{key}:{s[0]}\n"
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
				obj[key] = line[d+1:] # skip delimeter and space following

	# Lazy fix, I don't feel like tracking down the bug causing an
	# empty insertion here.
	result.pop()
	return result

# Assume file has read perms
def dpkg_status_load(fileobj):
	# NOTE: May be faster to use fewer reads by doing things manually.
	#       For now I'm just taking the short path and using Python's internal
	#       buffer system.
	# buff=bytearray(204800);
	# Read 100kb each pass; 102400 bytes
	result=[]; obj=OrderedDict(); key=None;

	for line in fileobj:
		line = line[:-1] # Trim off trailing newline character
		if len(line) == 0:
			result.append(obj)
			obj=OrderedDict(); key=None;
		else:
			if line[0] == " " and key is not None:
				obj[key] += f"\n{line[1:]}"
			else:
				d = line.find(":")
				key = line[0:d]
				obj[key] = line[d+1:] # skip delimeter and space following


	return result

# Assume file has write perms
def dpkg_status_dump(status, fileobj):
	# Write from where the file spool is left off. Let the user handle that
	# outside this function. Do writes in 50kb or greater chunks.
	buffer=""; i=0; l=len(status); bytes_written = 0
	while i < l:
		buffer=""
		n = i+200 # precalc
		for entry in status[i:n if n < l else l]:
			for key, value in entry:
				s = value.split("\n")
				buffer += f"{key}:{s[0]}\n"
				for i in range(1, len(s)):
					buffer += f" {s[i]}\n"
			buffer += "\n"

		# TODO: Rewrite this function using raw binary IO so the return
		#       value is more useful.
		bytes_written += fileobj.write(buffer)
		i = n


	return bytes_written


old_root_status_path = Path(APPDATA, "root-status.old")
root_status_path = Path(TEMPDIR, "root-status")

if not old_root_status_path.exists():
	# TODO: Maybe warn the user that in this scenario that this file's missing
	#       because it could mean either corruption or the internal status
	#       risks being mismanaged. Both situations aren't great.
	copy(str(root_status_path), str(old_root_status_path))
	exit(0)

root_status_raw = None
try: root_status_raw = root_status_path.open().read()
except Exception as e:
	print(str(e), file=sys.stderr)
	exit(1)

with old_root_status_path.open() as old_status:
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
user_status_file = None
try: user_status_file = Path(TEMPDIR, "user-status").open("r+")
except Exception as e:
	print(str(e), file=sys.stderr)
	exit(1)


user_status = dpkg_status_load(user_status_file)
root_status = dpkg_status_loads(root_status_raw)


# First we have to find out what packages we actually have in the user store.
# From there, we'll overwrite entries from the root status file using the user
# entreis. Since the data within the user data store should always be current
# we can assume that no other packages have changed since our last invocation.
package_container = Path(CHROOT,"var/lib/dpkg/info")
user_packages = tuple(f.stem for f in package_container.iterdir())

def only_user_packages(e):
	try:
		if e["Package"] in user_packages and e["Architecture"] in ("all", ARCH):
			return True
		elif f"{e['Package']}:{e['Architecture']}" in user_packages:
			return True
		else:
			return False
	except Exception as err:
		print(e, file=sys.stderr)
		return False

user_entries = filter(only_user_packages, user_status)
user_entries = dict((obj["Package"]+":"+obj["Architecture"],obj) for obj in user_entries)

def replace_with_user_entries(e):
	try:
		x = user_entries[e["Package"]+":"+e["Architecture"]]
		return x
	except KeyError as err:
		pass
	return e

user_status = list(map(replace_with_user_entries, root_status))
# TODO: look into backing up the user status file post-update

user_status_file.seek(0, 0) # seek to the beginning of file before overwrite
dpkg_status_dump(user_status, user_status_file)

# NOTE: Use tell and not the characters written value from dpkg_status_dump
#       because truncate uses bytes, not characters. This will always cause
#       issues
#         TODO: Suggest a PEP for the FS system to add a specialized truncate
#               method for TextIOWrapper that accepts characters; not rly
#               possible. Or start a RFC on the Python TextIOWrappper.write
user_status_file.truncate(user_status_file.tell())
