module core.stdc.fenv;

alias wchar_t = dchar;

// fenv.d content:
struct fenv_t
{
    c_ulong __cw;
}

import core.stdc.config: c_ulong;
alias fexcept_t = c_ulong;

enum FE_DFL_ENV = cast(fenv_t*)(-1);

version (ARM)
{
    enum FE_INEXACT =   0x0010;
    enum FE_UNDERFLOW = 0x0008;
    enum FE_OVERFLOW =  0x0004;
    enum FE_DIVBYZERO = 0x0002;
    enum FE_INVALID =   0x0001;

    version (D_HardFloat)
    {
        enum FE_TONEAREST =     0x00000000;
        enum FE_DOWNWARD =      0x00800000;
        enum FE_UPWARD =        0x00400000;
        enum FE_TOWARDZERO =    0x00c00000;
    }
    else
    {
        enum FE_TONEAREST =     0x0000;
        enum FE_DOWNWARD =      0x0001;
        enum FE_UPWARD =        0x0002;
        enum FE_TOWARDZERO =    0x0003;
    }
}
else version (RISCV32)
{
    enum FE_INEXACT =   0x01;
    enum FE_UNDERFLOW = 0x02;
    enum FE_OVERFLOW =  0x04;
    enum FE_DIVBYZERO = 0x08;
    enum FE_INVALID =   0x10;

    enum FE_TONEAREST =     0x0;
    enum FE_TOWARDZERO =    0x1;
    enum FE_DOWNWARD =      0x2;
    enum FE_UPWARD =        0x3;
}

enum FE_ALL_EXCEPT = FE_INEXACT
                    | FE_UNDERFLOW
                    | FE_OVERFLOW
                    | FE_DIVBYZERO
                    | FE_INVALID;
