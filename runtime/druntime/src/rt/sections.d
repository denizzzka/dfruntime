/**
 *
 * Copyright: Copyright Digital Mars 2000 - 2012.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Walter Bright, Sean Kelly, Martin Nowak
 * Source: $(DRUNTIMESRC rt/_sections.d)
 */

module rt.sections;

version (LDC)
    public import rt.sections_ldc;

version (OSX)
    version = Darwin;
else version (iOS)
    version = Darwin;
else version (TVOS)
    version = Darwin;
else version (WatchOS)
    version = Darwin;

version (CRuntime_Glibc)
    public import rt.sections_elf_shared;
else version (CRuntime_Musl)
    public import rt.sections_elf_shared;
else version (FreeBSD)
    public import rt.sections_elf_shared;
else version (NetBSD)
    public import rt.sections_elf_shared;
else version (OpenBSD)
{
    /**
     * OpenBSD is missing support needed for elf_shared.
     * See the top of sections_solaris.d for more info.
     */

    public import rt.sections_solaris;
}
else version (DragonFlyBSD)
    public import rt.sections_elf_shared;
else version (Solaris)
    public import rt.sections_solaris;
else version (Darwin)
{
    version (LDC)
        public import rt.sections_elf_shared;
    else version (X86_64)
        public import rt.sections_osx_x86_64;
    else version (X86)
        public import rt.sections_osx_x86;
    else
        static assert(0, "unimplemented");
}
else version (CRuntime_DigitalMars)
    public import rt.sections_win32;
else version (CRuntime_Microsoft)
{
    version (LDC)
        public import rt.sections_elf_shared;
    else
        public import rt.sections_win64;
}
else version (CRuntime_Bionic)
    public import rt.sections_elf_shared;
else version (CRuntime_UClibc)
    public import rt.sections_elf_shared;
else version (DruntimeAbstractRt)
    public import external.rt.sections;
else
    static assert(0, "unimplemented");

version (Windows)
{
}
else version (Shared)
{
    static assert(is(typeof(&pinLoadedLibraries) == void* function() nothrow @nogc));
    static assert(is(typeof(&unpinLoadedLibraries) == void function(void*) nothrow @nogc));
    static assert(is(typeof(&inheritLoadedLibraries) == void function(void*) nothrow @nogc));
    static assert(is(typeof(&cleanupLoadedLibraries) == void function() nothrow @nogc));
}
