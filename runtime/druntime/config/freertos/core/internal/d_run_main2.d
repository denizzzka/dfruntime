module core.internal.d_run_main2;

import rt.dmain2;
import core.stdc.stdio: stderr, stdout, fflush, fprintf;
import core.stdc.stdlib: EXIT_FAILURE, EXIT_SUCCESS;

/// Type of the D main() function (`_Dmain`).
private alias extern(C) int function(char[][] args) MainFunc;

package int _d_run_main2(char[][] args, size_t totalArgsLength, MainFunc mainFunc)
{
    int result;
    args = null;

    auto useExceptionTrap = false; //parseExceptionOptions();

    void tryExec(scope void delegate() dg)
    {
        if (useExceptionTrap)
        {
            try
            {
                dg();
            }
            catch (Throwable t)
            {
                _d_print_throwable(t);
                result = EXIT_FAILURE;
            }
        }
        else
        {
            dg();
        }
    }

    // NOTE: The lifetime of a process is much like the lifetime of an object:
    //       it is initialized, then used, then destroyed.  If initialization
    //       fails, the successive two steps are never reached.  However, if
    //       initialization succeeds, then cleanup will occur even if the use
    //       step fails in some way.  Here, the use phase consists of running
    //       the user's main function.  If main terminates with an exception,
    //       the exception is handled and then cleanup begins.  An exception
    //       thrown during cleanup, however, will abort the cleanup process.
    void runAll()
    {
        if (rt_init())
        {
            auto utResult = runModuleUnitTests();
            assert(utResult.passed <= utResult.executed);
            if (utResult.passed == utResult.executed)
            {
                if (utResult.summarize)
                {
                    if (utResult.passed == 0)
                        .fprintf(.stderr, "No unittests run\n");
                    else
                        .fprintf(.stderr, "%d modules passed unittests\n",
                                 cast(int)utResult.passed);
                }
                if (utResult.runMain)
                    tryExec({ result = mainFunc(args); });
                else
                    result = EXIT_SUCCESS;
            }
            else
            {
                if (utResult.summarize)
                    .fprintf(.stderr, "%d/%d modules FAILED unittests\n",
                             cast(int)(utResult.executed - utResult.passed),
                             cast(int)utResult.executed);
                result = EXIT_FAILURE;
            }
        }
        else
            result = EXIT_FAILURE;

        if (!rt_term())
            result = (result == EXIT_SUCCESS) ? EXIT_FAILURE : result;
    }

    tryExec(&runAll);

    if (.fflush(.stdout) != 0)
    {
        //TODO: strerror() contains huge amount of strings, isn't appropriate for tiny bare-metal devices
        //~ .fprintf(.stderr, "Failed to flush stdout: %s\n", .strerror(.errno));
        if (result == 0)
        {
            result = EXIT_FAILURE;
        }
    }

    return result;
}
