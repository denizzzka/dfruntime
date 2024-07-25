///
module core.stdc.wchar_;

nothrow:
@nogc:
extern(C):

public import core.stdc.stddef: wchar_t;

alias wint_t = wchar_t;

import core.stdc.stdio: _iobuf, FILE;

int fputwc(wchar_t c, _iobuf* fp);
int fgetwc(_iobuf* fp);
int fwide(FILE* stream, int mode) @safe;
