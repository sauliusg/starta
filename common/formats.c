/*---------------------------------------------------------------------------*\
**$Author: saulius $
**$Date: 2004-11-13 20:51:21 +0200 (Sat, 13 Nov 2004) $ 
**$Revision: 71 $
**$URL: svn+ssh://localhost/home/saulius/svn-repositories/compilers/common/common.c $
\*---------------------------------------------------------------------------*/

/* exports: */
#include <formats.h>

/* uses: */
#include <stdlib.h>

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
