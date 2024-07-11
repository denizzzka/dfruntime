module core.thread.stack;

version (GNU)
{
    version (GNU_StackGrowsDown)
        enum isStackGrowingDown = true;
    else
        enum isStackGrowingDown = false;
}
else version (LDC)
{
    // The only LLVM targets as of LLVM 16 with stack growing *upwards* are
    // apparently NVPTX and AMDGPU, both without druntime support.
    // Note that there's an analogous `version = StackGrowsDown` in
    // core.thread.fiber.
    enum isStackGrowingDown = true;
}
else
{
    version (X86) enum isStackGrowingDown = true;
    else version (X86_64) enum isStackGrowingDown = true;
    else static assert(0, "It is undefined how the stack grows on this architecture.");
}
