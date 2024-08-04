///
module core.stdc.wchar_;

nothrow:
@nogc:
extern(C):

public import core.stdc.stddef: wchar_t;

alias wint_t = wchar_t;

import core.stdc.stdio: FILE;

int fputwc(wchar_t c, FILE* fp);
int fgetwc(FILE* fp);
int fwide(FILE* stream, int mode) @safe;
pure size_t wcslen(scope const wchar_t* s);
