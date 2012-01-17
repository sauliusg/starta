/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* uses: */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sllist.h>
#include <cexceptions.h>

static char *strings[] = {
    "one",
    "two",
    "three",
    NULL
};

void strdispose( char * volatile *str )
{
    if( str && *str ) {
	free( *str );
	*str = NULL;
    }
}

#define create_string_list( LIST, VALUE, NEXT, EXCEPTION ) \
    create_sllist( LIST, (void**)(VALUE), \
                   (dispose_function_t)strdispose, \
                   NEXT, \
                   EXCEPTION )

#define push_shared_string( LIST, VALUE, EXCEPTION ) \
    sllist_push_shared_data( LIST, (void*)(VALUE), \
                             (delete_function_t)free, \
                             (dispose_function_t)NULL, \
                             (share_function_t)strdup, \
                             EXCEPTION )

int main( int argc, char *argv[] )
{
    cexception_t inner;
    SLLIST * volatile string_list = NULL;
    SLLIST * curr = NULL;
    int i;
    int n = 0;

    cexception_guard( inner ) {
	char *init_string = strdup( "initial" );
	create_string_list( &string_list, &init_string,
			    /*next = */ NULL, &inner );
	for( i = 0; strings[i] != NULL; i++ ) {
	    push_shared_string( &string_list, strings[i], &inner );
	}
    }
    cexception_catch {
	fprintf( stderr, "%s: %s\n", argv[0], cexception_message( &inner ));
    }

    n = 0;
    foreach_sllist_node( curr, string_list ) {
	char *val = sllist_data( curr );
	printf( "%2d: %s\n", n, val );
	n++;
    }

    dispose_sllist( &string_list );
    return 0;
}
