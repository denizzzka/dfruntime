/**
 This module contains the code for C main and any call(s) to initialize the
 D runtime and call D main.

  Copyright: Copyright Digital Mars 2000 - 2019.
  License: Distributed under the
       $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
     (See accompanying file LICENSE)
  Source: $(DRUNTIMESRC core/_internal/_entrypoint.d)
*/
module core.internal.entrypoint;

enum exposeDefaultDRunMain = true;

/**
A template containing C main and any call(s) to initialize druntime and
call D main.  Any module containing a D main function declaration will
cause the compiler to generate a `mixin _d_cmain();` statement to inject
this code into the module.
*/
template _d_cmain()
{
    extern(C)
    {
        int _Dmain(char[][] args);

        version (Windows)
        {
            int _d_wrun_main(int argc, wchar** wargv, void* mainFunc);

            int wmain(int argc, wchar** wargv)
            {
                pragma(LDC_profile_instr, false);
                return _d_wrun_main(argc, wargv, &_Dmain);
            }
        }
        else version (Posix)
        {
            int _d_run_main(int argc, char** argv, void* mainFunc);

            int main(int argc, char** argv)
            {
                pragma(LDC_profile_instr, false);
                return _d_run_main(argc, argv, &_Dmain);
            }

            // Solaris, for unknown reasons, requires both a main() and an _main()
            version (Solaris)
            {
                int _main(int argc, char** argv)
                {
                    pragma(LDC_profile_instr, false);
                    return main(argc, argv);
                }
            }
        }
        else
            static assert(false);
    }
}
