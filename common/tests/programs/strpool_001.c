// Test String pools.
// Compile as:
// cc -o try -I common -I cexceptions main.c common/strpool.c cexceptions/libcexceptions.a

#include <stdio.h>
#include <strpool.h>
#include <allocx.h>
#include <cexceptions.h>

int main( int argc, char *argv[] )
{
    int i;
    STRPOOL *pool = new_strpool( NULL );

    printf( "Hi!\n" );

    char *strings[] = {
        "One", "Two", "Three", "Four", "Five", NULL
    };

    int idx[sizeof(strings)/sizeof(strings[0])];

    for( i = 0; strings[i] != NULL; i ++ ) {
        idx[i] = strpool_add_string( pool, strings[i], NULL );
    }

    for( i = 0; strings[i] != NULL; i ++ ) {
        printf( "%i:\t%d\n", i, idx[i] );
    }

    char *str3 = obtain_string_from_strpool( pool, 3 );
    printf( "Obtained \"%s\"\n", str3 );
    freex( str3 );

    strpool_add_string( pool, "One more string", NULL );
    
    for( i = 0; strings[i] != NULL; i ++ ) {
        char *str = obtain_string_from_strpool( pool, i );
        printf( "%i:\t%s\n", i, str );
        freex( str );
    }

    i = strpool_add_string( pool, "Before last", NULL );
    i = strpool_add_string( pool, "Very last", NULL );

    str3 = obtain_string_from_strpool( pool, i );
    printf( "Obtained string %d: \"%s\"\n", i, str3 );
    freex( str3 );

    dispose_strpool( &pool );
    
    return 0;
}
