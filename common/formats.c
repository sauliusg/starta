/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <formats.h>

/* uses: */
#include <stdlib.h>
#include <unistd.h>

const char *size_t_format( void )
{
    static char *fmt;

    if( !fmt ) {
	if( sizeof(size_t) == sizeof(int))
	    fmt = "d";
	else if( sizeof(size_t) == sizeof(long))
	    fmt = "ld";
	else if( sizeof(size_t) == sizeof(long long))
	    fmt = "Ld";
	else
	    fmt = "d";
    }
    return fmt;
}

const char *ssize_t_format( void )
{
    static char *fmt;

    if( !fmt ) {
	if( sizeof(ssize_t) == sizeof(int))
	    fmt = "d";
	else if( sizeof(ssize_t) == sizeof(long))
	    fmt = "ld";
	else if( sizeof(ssize_t) == sizeof(long long))
	    fmt = "Ld";
	else
	    fmt = "d";
    }
    return fmt;
}
