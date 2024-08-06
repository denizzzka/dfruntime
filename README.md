DFRuntime - is a fork of LDC DRuntime
===============================

<sup>(In fact, for convenience of maintenance, this is a fork of whole [ldc](https://github.com/ldc-developers/ldc))</sup>

# Rationale

I think that [this way](https://github.com/dlang/dmd/pull/15822#issue-1996484133) of organizing DRuntime code is right way.

And I want to program for all sorts of MCUs/CPUs/OSes/etc using same my favorite programming language.

# Build for Linux

All builds will be done using [Meson build system](https://mesonbuild.com/) because it is need to set up a huge number of build options for the all parts of build.

First step is to make sure that nothing is broken and everything works under usual Linux.
Build druntime for Linux:
```
> git clone --recurse-submodules https://github.com/denizzzka/dfruntime.git
> cd dfruntime/
> meson setup -Dbuildtype=release --prefix=$(pwd)/install_linux_release/ build_linux_release
> ninja -C build_linux_release/ libdruntime-ldc-shared.so libphobos2-ldc-shared.so install
```

Now we can build something with this DRuntime and Phobos binaries:
```
> ldc2 -conf=install_linux_release/etc/ldc2_tagged.conf some_app.d
```

Thus, you can use this fork as your usual regular DRuntime.

# Build for ARM Cortex-M4

Ok, lets build D runtime for ARM Cortex-M4. Runtime will use [FreeRTOS](https://www.freertos.org/) as "threads manager"
and [picolibc](https://github.com/picolibc/picolibc) as libc:
```
> meson setup -Doptimization=s --prefix=$(pwd)/install_cortex-m4/ --cross-file meson/arm_cortex_m4_cross.ini build_debug_druntime_cortex-m4
> ninja -C build_debug_druntime_cortex-m4/ libdruntime-ldc-debug.a libphobos2-ldc-debug.a install
```

Make sure that it was actually obtained ARM 32 bit static library:
```
> LANG=C readelf -h install_cortex-m4/lib/libdruntime-ldc-debug.a | head -n 25

File: install_cortex-m4/lib/libdruntime-ldc-debug.a(atomic.o)
ELF Header:
  Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00
  Class:                             ELF32
  Data:                              2's complement, little endian
  Version:                           1 (current)
  OS/ABI:                            UNIX - System V
  ABI Version:                       0
  Type:                              REL (Relocatable file)
  Machine:                           ARM
  Version:                           0x1
  Entry point address:               0x0
  Start of program headers:          0 (bytes into file)
  Start of section headers:          49888 (bytes into file)
  Flags:                             0x5000000, Version5 EABI
  Size of this header:               52 (bytes)
  Size of program headers:           0 (bytes)
  Number of program headers:         0
  Size of section headers:           40 (bytes)
  Number of section headers:         181
  Section header string table index: 1

File: install_cortex-m4/lib/libdruntime-ldc-debug.a(attribute.o)
ELF Header:
```

That's all!

But there is another important point: in order to use obtained druntime binary you will also need compiled FreeRTOS and Picolibc binaries.
You will need to link them together with your application.

<sup>Original README.md:</sup>

LDC – the LLVM-based D Compiler
===============================

[![Latest release](https://img.shields.io/github/v/release/ldc-developers/ldc?include_prereleases&label=latest)][8]
[![Latest stable release](https://img.shields.io/github/v/release/ldc-developers/ldc?label=stable)][0]
[![Build status](https://img.shields.io/circleci/project/github/ldc-developers/ldc/master?logo=CircleCI&label=CircleCI)][3]
[![Build status](https://img.shields.io/cirrus/github/ldc-developers/ldc/master?label=Cirrus%20CI&logo=Cirrus%20CI)][4]
[![Build status](https://img.shields.io/github/actions/workflow/status/ldc-developers/ldc/main.yml?branch=master&label=GitHub%20Actions%20%28main%29&logo=github)][7]
[![Build status](https://img.shields.io/github/actions/workflow/status/ldc-developers/ldc/supported_llvm_versions.yml?branch=master&label=GitHub%20Actions%20%28LLVM%29&logo=github)][7]

The LDC project provides a portable D programming language compiler
with modern optimization and code generation capabilities.

The compiler uses the official DMD frontend to support the latest
version of D2, and relies on the LLVM Core libraries for code
generation.

LDC is fully Open Source; the parts of the source code not taken/adapted from
other projects are BSD-licensed (see the LICENSE file for details).

Please consult the D wiki for further information:
https://wiki.dlang.org/LDC

D1 is no longer available; see the `d1` Git branch for the last
version supporting it.


Installation
------------

### From a pre-built package

Portable stand-alone binary builds (and a Windows installer) for common
platforms (incl. Linux, macOS, Windows, FreeBSD and Android) are available
at the [GitHub release page](https://github.com/ldc-developers/ldc/releases).
For Windows, the [Visual D installer](https://rainers.github.io/visuald/visuald/StartPage.html)
also comes with a bundled LDC.

For bleeding-edge users, we also provide the [latest successful Continuous
Integration builds](https://github.com/ldc-developers/ldc/releases/tag/CI)
with enabled LLVM & LDC assertions (increasing compile times by roughly 50%).

The [dlang.org install script](https://dlang.org/install.html) can also be
used to install these official packages from GitHub:

    curl -fsS https://dlang.org/install.sh | bash -s ldc

In addition, LDC is available from various package managers (but note that
these packages are **community-maintained, might be outdated and not offer
the full feature set of official packages from GitHub**):

|              | Command                                      |
| ------------ | -------------------------------------------- |
| Alpine Linux | `apk add ldc`                              |
| Android      | in [Termux app](https://play.google.com/store/apps/details?id=com.termux&hl=en): `pkg install ldc` |
| Arch Linux   | `pacman -S ldc`                              |
| Chocolatey   | `choco install ldc`                          |
| Debian       | `apt install ldc`                            |
| Docker       | `docker pull dlang2/ldc-ubuntu`              |
| Fedora       | `dnf install ldc`                            |
| FreeBSD      | `pkg install ldc`                            |
| Gentoo       | `layman -a ldc`                              |
| Homebrew     | `brew install ldc`                           |
| Nix/NixOS    | `nix-env -i ldc`                             |
| OpenBSD      | `pkg_add ldc`                                |
| Snap         | `snap install --classic --channel=edge ldc2` |
| Ubuntu       | `apt install ldc`                            |
| Void         | `xbps-install -S ldc`                        |

### Building from source

In-depth material on building and installing LDC and the standard
libraries is available on the project wiki for
[Linux, macOS, BSD, and Android](http://wiki.dlang.org/Building_LDC_from_source) and
[Windows](http://wiki.dlang.org/Building_and_hacking_LDC_on_Windows_using_MSVC).

If you have a working C++/D build environment, CMake, and a recent LLVM
version (≥ 11) available, there should be no big surprises. Do not
forget to make sure the Phobos submodule is up to date:

    $ cd ldc
    $ git submodule update --init

(DMD, GDC and LDC are supported as host compilers. For bootstrapping
purposes, we recommend GDC via its `gdmd` wrapper.)

Cross-compilation
-----------------

Similar to other LLVM-based compilers, cross-compiling with LDC is simple.
Full instructions and example invocations are provided on the dedicated
[Wiki page](https://wiki.dlang.org/Cross-compiling_with_LDC).

#### Targeting Android

You can find full instructions on cross-compiling or natively compiling
for Android [on the wiki](https://wiki.dlang.org/Build_D_for_Android).

Contact
-------

The best way to get in touch with the developers is either via the
[digitalmars.D.ldc forum/newsgroup/mailing list](https://forum.dlang.org)
or our [Gitter chat](http://gitter.im/ldc-developers/main).
There is also the #ldc IRC channel on FreeNode.

For further documentation, contributor information, etc. please see
[the D wiki](https://wiki.dlang.org/LDC).

Feedback of any kind is very much appreciated!


[0]: https://github.com/ldc-developers/ldc/releases/latest
[3]: https://circleci.com/gh/ldc-developers/ldc/tree/master
[4]: https://cirrus-ci.com/github/ldc-developers/ldc/master
[7]: https://github.com/ldc-developers/ldc/actions?query=branch%3Amaster
[8]: https://github.com/ldc-developers/ldc/releases
