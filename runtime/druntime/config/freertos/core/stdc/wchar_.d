///
module core.stdc.wchar_;

nothrow:
@nogc:

public import core.stdc.stddef: wchar_t;

alias wint_t = wchar_t;

import core.stdc.stdio: _iobuf;

extern(C) int fputwc(wchar_t c, _iobuf* fp);
extern(C) int fgetwc(_iobuf* fp);
