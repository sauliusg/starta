// Test String pools.
// Compile as:
// cc -o try -I common -I cexceptions main.c common/strpool.c cexceptions/libcexceptions.a

#include <stdio.h>
#include <strpool.h>
#include <cexceptions.h>

int main( int argc, char *argv[] )
{
    printf( "Hi!\n" );

    char *strings[] = {
        "One", "Two", "Three", "Four", "Five", NULL
    };

    int idx[sizeof(strings)/sizeof(strings[0])];

    for( int i = 0; strings[i] != NULL; i ++ ) {
        idx[i] = pool_add_string( strings[i], NULL );
    }

    char *str3 = obtain_string_from_pool(3);
    printf( "Obtained \"%s\"\n", str3 );
    free( str3 );

    pool_add_string( "One more string", NULL );
    
    for( int i = 0; strings[i] != NULL; i ++ ) {
        char *str = obtain_string_from_pool( i );
        printf( "%i:\t%s\n", i, str );
        free( str );
    }

    int i;
    i = pool_add_string( "Before last", NULL );
    i = pool_add_string( "Very last", NULL );

    str3 = obtain_string_from_pool( i );
    printf( "Obtained string %d: \"%s\"\n", i, str3 );
    free( str3 );

    free_pool();
    
    return 0;
}
