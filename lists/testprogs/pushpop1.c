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

#define push_string( LIST, VALUE, EXCEPTION ) \
    sllist_push_data( LIST, (void*)(VALUE), \
                      (break_cycle_function_t)NULL, \
                      (delete_function_t)NULL, \
                      (dispose_function_t)NULL, \
                      EXCEPTION )

int main( int argc, char *argv[] )
{
    cexception_t inner;
    SLLIST * volatile string_list = NULL;
    char * curr = NULL;
    char * one = "one";
    char * two = "two";
    char * three = "three";

    cexception_guard( inner ) {
	push_string( &string_list, &one, &inner );
	push_string( &string_list, &two, &inner );
	push_string( &string_list, &three, &inner );
    }
    cexception_catch {
	fprintf( stderr, "%s: %s\n", argv[0], cexception_message( &inner ));
    }

    curr = sllist_pop_data( &string_list );
    printf( "%s\n", curr ? curr : "(null)" );

    curr = sllist_pop_data( &string_list );
    printf( "%s\n", curr ? curr : "(null)" );

    curr = sllist_pop_data( &string_list );
    printf( "%s\n", curr ? curr : "(null)" );

    dispose_sllist( &string_list );
    return 0;
}
