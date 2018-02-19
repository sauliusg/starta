#include <stdio.h>
#include <stdint.h>
#include <alloccell.h>

int main()
{
    printf( "sizeof(alloccell_t) = %zd\n", sizeof(alloccell_t) );
    printf( "sizeof(stackcell_t) = %zd\n", sizeof(stackcell_t) );
    printf( "sizeof(stacunion_t) = %zd\n", sizeof(union stackunion) );
    return 0;
}
