// COMPILE_SEPARATELY:
// EXTRA_SOURCES: imports/test23722b.d
// rEQUIRED_ARGS: -betterC // disabled for LDC as the test is 'buggy' and betterC not required at all
// https://issues.dlang.org/show_bug.cgi?id=23722
// Lambdas are mangled incorrectly when using multiple compilation units, resulting in incorrect code
import imports.test23722b;

bool f() {
    return b;
}

void main() {}
