/*---------------------------------------------------------------------------*\
**$Author: saulius $
**$Date$ 
**$Revision$
**$URL: svn+ssh://kolibris.ibt.lt/home/saulius/svn-repositories/compilers/lists/testprogs/test1.c $
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

static void strdispose( char * volatile *str )
{
    if( str && *str ) {
	free( *str );
	*str = NULL;
    }
}

static void create_string_list( SLLIST * volatile *list,
				char **value,
				SLLIST *next,
				cexception_t *exception )
{
    create_sllist( list, (void**)(value),
		   (dispose_function_t)strdispose,
                   next, exception );
}

static void push_shared_string( SLLIST * volatile *list,
				char *value,
				cexception_t *exception )
{
    sllist_push_shared_data( list, (void*)(value),
                             (delete_function_t)free,
                             (dispose_function_t)NULL,
                             (share_function_t)strdup,
                             exception );
}

static void print_string_list( SLLIST *string_list, char *trailer )
{
    SLLIST * curr = NULL;
    int n = 0;

    foreach_sllist_node( curr, string_list ) {
	char *val = sllist_data( curr );
	printf( "%2d: %s\n", n, val );
	n++;
    }
    if( trailer ) printf( "%s", trailer );
}

int main( int argc, char *argv[] )
{
    cexception_t inner;
    SLLIST * volatile string_list = NULL;
    int i;

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

    while( string_list ) {
	print_string_list( string_list, "\n" );
	sllist_swap( &string_list );
	print_string_list( string_list, "=====\n\n" );
	sllist_drop( &string_list );
    }

    dispose_sllist( &string_list );
    return 0;
}
