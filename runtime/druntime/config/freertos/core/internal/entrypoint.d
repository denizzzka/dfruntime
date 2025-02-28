/**
 * FreeRTOS implementation of _d_cmain template - entrypoint of D main
 *
 * Copyright: Copyright Denis Feklushkin 2024.
 * License: Distributed under the
 *      $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0).
 *    (See accompanying file LICENSE)
 * Authors:   Denis Feklushkin
 * Source: $(DRUNTIMESRC config/freertos/core/internal/entrypoint.d)
 */
module core.internal.entrypoint;

static import os = internal.binding;

enum exposeDefaultDRunMain = false;

import rt.dmain2;
import core.stdc.stdio: stderr, stdout, fflush, fprintf;
import core.stdc.stdlib: EXIT_FAILURE, EXIT_SUCCESS;

/// Type of the D main() function (`_Dmain`).
private alias extern(C) int function(char[][] args) MainFunc;

private extern (C) int _d_run_main2(char[][] args, size_t totalArgsLength, MainFunc mainFunc)
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

    // Return from main() is impossible for FreeRTOS, thus just calling exit()
    import core.stdc.stdlib: exit;
    exit(result);

    // return result;
}

nothrow:
@nogc:

struct MainTaskProperties
{
    ushort taskStackSizeWords; // words, not bytes!
    void* stackBottom; // filled out after task starts

    void setTaskStackSizeBytes(size_t s = ushort.max * 4)
    {
        taskStackSizeWords = cast(ushort) (s / 4);
    }
}

__gshared static MainTaskProperties mainTaskProperties;

/// Init FreeRTOS main task stack
void initMainStack()
{
    import core.internal.traits: externDFunc;
    alias getStackTop = externDFunc!("core.thread.common.getStackTop", void* function() nothrow @nogc);

    mainTaskProperties.taskStackSizeWords = 25 * 1024 / 4;

    // stack wasn't used yet, so assumed what we on top
    mainTaskProperties.stackBottom = getStackTop();
}

version (FreeRTOS_CreateMainLoop)
template _d_cmain()
{
    extern(C):

    version(ARM)
        void systick_interrupt_disable(); // provided by libopencm3
    else
        static assert(false, "Not implemented");

    int _Dmain(char[][] args);

    /// Type of the D main() function (`_Dmain`).
    private alias int function(char[][] args) MainFunc;

    int _d_run_main2(char[][] args, object.size_t totalArgsLength, MainFunc mainFunc);

    import core.internal.entrypoint: MainTaskProperties, mainTaskProperties;

    void _d_run_main(void* mtp)
    {
        import core.stdc.stdlib: _Exit;

        __gshared int main_ret = 7; // _d_run_main2 uncatched exception occured
        scope(exit)
        {
            systick_interrupt_disable(); // tell FreeRTOS to doesn't interfere with exiting code
            _Exit(main_ret); // It is impossible to escape from FreeRTOS main loop, thus just exit
        }

        main_ret = _d_run_main2(null, 0, &_Dmain);
    }

    int main(int argc, char** argv)
    {
        pragma(LDC_profile_instr, false);

        import core.internal.entrypoint: interruptsVector;
        import core.thread: DefaultTaskPriority;
        import internal.binding: xTaskCreate, vTaskStartScheduler, pdTRUE;

        auto creation_res = xTaskCreate(
            &_d_run_main,
            cast(const(char*)) "_d_run_main",
            mainTaskProperties.taskStackSizeWords, // usStackDepth
            cast(void*) &mainTaskProperties, // pvParameters*
            DefaultTaskPriority,
            null // task handler
        );

        if(creation_res != pdTRUE /* FIXME: pdPASS */)
            return 2; // task creation error

        // Init needed FreeRTOS interrupts handlers
        //~ import external.rt.dmain;

        assert(&interruptsVector.sv_call == cast (void*) 0x002c);
        assert(&interruptsVector.pend_sv == cast (void*) 0x0038);

        //~ immutable uint SCB_AIRCR_PRIGROUP_GROUP16_NOSUB = 0x3 << 8 + 0xf;
        //~ scb_set_priority_grouping(SCB_AIRCR_PRIGROUP_GROUP16_NOSUB);

        vTaskStartScheduler(); // infinity loop

        return 6; // Out of memory
    }
}
else
template _d_cmain()
{
    extern(C):

    int _Dmain(char[][] args);

    /// Type of the D main() function (`_Dmain`).
    private alias int function(char[][] args) MainFunc;

    int _d_run_main2(char[][] args, object.size_t totalArgsLength, MainFunc mainFunc);

    // To start D main() it is need to call this function from external code
    void _d_run_main()
    {
        import core.stdc.stdlib: _Exit;

        __gshared int main_ret = 7; // _d_run_main2 uncatched exception occured
        scope(exit)
        {
            _Exit(main_ret); // It is impossible to escape from FreeRTOS main loop, thus just exit
        }

        main_ret = _d_run_main2(null, 0, &_Dmain);
    }
}

static import ldc.attributes;

@(ldc.attributes.weak)
private extern(C) void vApplicationGetIdleTaskMemory(os.StaticTask_t** tcb, os.StackType_t** stackBuffer, uint* stackSize)
{
  __gshared static os.StaticTask_t idle_TCB;
  __gshared static os.StackType_t[os.configMINIMAL_STACK_SIZE] idle_Stack;

  *tcb = &idle_TCB;
  *stackBuffer = &idle_Stack[0];
  *stackSize = os.configMINIMAL_STACK_SIZE;
}

extern(C) void vApplicationStackOverflowHook(os.TaskHandle_t xTask, char* pcTaskName)
{
    import core.stdc.stdio;

    printf("Stack overflow at task \"%s\" (%p)\n", pcTaskName, xTask);

    while(true)
    {}
}

extern(C) void malloc_stats();

extern(C) void vApplicationTickHook(os.TaskHandle_t xTask, char* pcTaskName)
{
    //TODO: remove this
}

version (ARM)
{

/// ARM Cortex-M3 interrupts vector
extern(C) __gshared InterruptsVector* interruptsVector = null;

//TODO: move to ARM Cortex-M3 related module
struct InterruptsVector
{
    void* initial_sp_value;
    void* reset;
    void* nmi_handler;
    void* hard_fault;
    void* memory_manage_fault;
    void* bus_fault;
    void* usage_fault;
    void*[4] reserved1;
    void* sv_call;
    void*[2] reserved2;
    void* pend_sv;
    void* systick;
    void* irq;
}

}
