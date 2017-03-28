#include <stdio.h>
#include <stdint.h>

int main()
{
    printf( "sizeof(intmax_t)  = %jd\n", (intmax_t)sizeof(intmax_t) );
    printf( "sizeof(ssize_t)   = %jd\n", (intmax_t)sizeof(ssize_t) );
    printf( "sizeof(void*)     = %jd\n", (intmax_t)sizeof(void*) );
    printf( "sizeof(int)       = %jd\n", (intmax_t)sizeof(int) );
    printf( "sizeof(long)      = %jd\n", (intmax_t)sizeof(long) );
    printf( "sizeof(long long) = %jd\n", (intmax_t)sizeof(long long) );

    long long i = 1000000000000LL;

    printf( "long long i = %jd\n", (intmax_t)i );

    return 0;
}
