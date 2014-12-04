/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __GRAMMAR_Y_H
#define __GRAMMAR_Y_H

#include <thrcode.h>
#include <cexceptions.h>

typedef enum {
  COMPILER_OK = 0,
  COMPILER_UNRECOVERABLE_ERROR,
  COMPILER_COMPILATION_ERROR,

  last_COMPILER_ERROR
} compiler_error_t;

THRCODE *new_thrcode_from_file( char *filename, char **include_paths,
                                cexception_t *ex );

void compiler_printf( cexception_t *ex, char *format, ... );

int compiler_yy_error_number( void );
void compiler_yy_reset_error_count( void );

void compiler_yy_debug_on( void );
void compiler_yy_debug_off( void );

#endif