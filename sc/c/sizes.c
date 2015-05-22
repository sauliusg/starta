#include <stdio.h>
#include <stdint.h>

int main()
{
    printf( "sizeof(intmax_t) = %jd\n", sizeof(intmax_t) );
    printf( "sizeof(ssize_t)  = %jd\n", sizeof(ssize_t) );
    printf( "sizeof(void*)    = %jd\n", sizeof(void*) );
    printf( "sizeof(int)      = %jd\n", sizeof(int) );
    return 0;
}
