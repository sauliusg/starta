/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <implementation.h>

/* uses: */
#include <string.h>

int implementation_has_attribute( char *attribute )
{
    if( strcmp( attribute, "element_size" ) == 0 ) {
        return 0;
    }
    if( strcmp( attribute, "element_align" ) == 0 ) {
        return 0;
    }
    return 1;
}

int implementation_has_format( char format )
{
    if( format == 's' ) return 0;
    return 1;
}
