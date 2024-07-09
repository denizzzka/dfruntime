module core.internal.abort;

/*
 * Use instead of assert(0, msg), since this does not print a message for -release compiled
 * code, and druntime is -release compiled.
 */
void abort(scope string msg, scope string filename = __FILE__, size_t line = __LINE__) @nogc nothrow @safe
{
    import core.stdc.stdlib: c_abort = abort;

    // use available OS system calls to print the message to stderr
    import core.internal.print_err: writeStr;

    import core.internal.string;
    UnsignedStringBuf strbuff = void;

    // write an appropriate message, then abort the program
    writeStr("Aborting from ", filename, "(", line.unsignedToTempString(strbuff), ") ", msg);
    c_abort();
}
