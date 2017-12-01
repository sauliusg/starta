/*---------------------------------------------------------------------------*\
** $Author$
** $Date$ 
** $Revision$
** $URL$
\*---------------------------------------------------------------------------*/

/* exports: */

#include <bytecode_file.h>

int bytecode_file_calculate_header_size( void )
{
    return sizeof( bytecode_file_hdr_t );
}

char *bytecode_file_name( bytecode_file_hdr_t *hdr )
{
    return hdr->filename.ptr;
}
