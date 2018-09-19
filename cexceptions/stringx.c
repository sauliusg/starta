/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <stringx.h>

/* uses: */
#include <string.h>
#include <allocx.h>

#define merror( EX ) cexception_raise_in( EX, allocx_subsystem, \
					  ALLOCX_NO_MEMORY,     \
					  "Not enough memory" )

char *strdupx( const char *str, cexception_t *ex )
{
    void *s =NULL;
    if( str ) {
	// s = strdup( str );
        s = mallocx( strlen(str) + 1, ex );
	if( !s ) merror( ex );
        strcpy( s, str );
    }
    return s;
}
