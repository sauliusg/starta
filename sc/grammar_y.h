/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __SNAIL_Y_H
#define __SNAIL_Y_H

#include <thrcode.h>
#include <cexceptions.h>

typedef enum {
  SNAIL_OK = 0,
  SNAIL_UNRECOVERABLE_ERROR,
  SNAIL_COMPILATION_ERROR,

  last_SNAIL_ERROR
} snail_error_t;

THRCODE *new_thrcode_from_snail_file( char *filename, char **include_paths,
				      cexception_t *ex );

void snail_printf( cexception_t *ex, char *format, ... );

int snail_yy_error_number( void );
void snail_yy_reset_error_count( void );

void snail_yy_debug_on( void );
void snail_yy_debug_off( void );

#endif
