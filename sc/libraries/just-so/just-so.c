
/* This is small test file that contains one function, but no OPCODES
   array which is needed by the SC runtime interpreter. When
   attempting to load this library into the SC program, the compiler
   should detect this. */

#include <just-so.h>

int anything( int i )
{
    return i * i;
}
