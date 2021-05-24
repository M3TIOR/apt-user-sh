# APT User Suite Prototype
A suite of shell scripts that makes the APT suite, multi-user environment friendly.
This is an initial implementation targeted towards making the service available
to the public. I'll hopefully get to re-implementing this in Rust eventually.
That's my end goal, as having a native implementation carries a large
performance boost that this project absolutely needs.
But for right now my end goal is to just get this written. I need it for my own
dotfiles right away to simplify system portability.

### Why make this?
I started making this out of necessity and I'm one of few people who needs
or would want this. Most Linux users I know, have their own personal laptops.
They only need to worry about a single user environment where they're the
administrator. So I don't know how useful this will really be for anyone
else in the long run. There's one other project that I know about which attempts
to accomplish something similar, [notroot][notroot], but their focus is much
more narrow. My assumption is that there is some small group of individuals
who might be interested other than myself. NotRoot has 51 stars on github
at the time of writing and it was the only similar project I could find.

Beyond that, I think it's poor design for package management solutions not
to support multi-user environments as a standard. So I'm doing the APT team
a favor and filling in the gap they left out.


## What can this project do?

### Dependencies? No problem.
Since it depends on the APT suite
to function, it can download it's own dependencies. If you're a system
administrator and want to keep this project from bloating your `$HOME` directory
or the project failed to download the deps on it's own,
the projects dependent packages for each supported system are as follows:

 * Ubuntu, Debian `coreutils procps psmisc util-linux proot unionfs-fuse`

It may work on more systems than the ones listed so try them out before
filling a bug report.


### User packages!
This is kinda the whole point. You can add your own packages to your `$HOME`
directory using an `apt`-like CLI interface. Though this project's goal isn't to
build a GUI or ensure compatibility with existing APT GUIs like `aptitude`.

Just do the following to install the `tomb` package into your user directory:
```sh
apt-user.sh install tomb;
```

Since this package is a light wrapper around the rest of the APT suite, you
can pass modifier arguments suitable for the native `apt` or `apt-get` to the
respective commands.
```sh
apt-user.sh install python -d; # Downloads but doesn't install.
```

For a full list of supported commands and how they work...
```sh
apt-user.sh --help
```

### How does this work?
`apt-user` uses a FUSE (FileSystem in User Space)
UnionFS mount both the root and user directories together. The root directory
is made read only, and the user directory is write-over. The user root directory
is read before any files in the system root. Then it uses proot to emulate
a chroot within the UnionFS.


### Benefits when compared to other methods?
 * This reduces bloat when compared to a full dedicated chroot for user
   packages because you only need to fetch what doesn't already exist.
 * What does exist in the system can also be updated selectively without
   intervention of the root user based on the existing user's needs.
 * Since packages are managed within APT, you have most of it's benefits;
   including but not limited to, dependency tracking, hash validation,
   familiar UI and deterministic installation.


### Limitations?
 * This package is merely a wrapper for APT services. The main TUI `apt`,
   isn't fully emulated by this script, nor are all the features of other
   tools.
 * Since the root user has no awareness of your package store's lock state,
   there is a small chance that if the root user modifies the root store while
   yours is being modified, it could corrupt your package store.
 * This doesn't modify the paths package programs search for their assets
   within your system. So if programs search for assets within `usr/lib/share`
   for example, then they may break or fail to load because the assets were
   instead installed into the user package store chroot.
 * This package can't notify you when the root user has uninstalled packages
   your local store depends on. So your applications may fail unexpectedly
   if the sysadmin does spring cleaning. However, this program can automatically
   detect what packages changed in between it's executions, so it will rectify
   missing packages the next time it runs.


[notroot]: https://github.com/Gregwar/notroot
