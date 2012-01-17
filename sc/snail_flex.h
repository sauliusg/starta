/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __SNAIL_FLEX_H
#define __SNAIL_FLEX_H

#include <stdio.h>
#include <unistd.h> /* for ssize_t */
#include <cexceptions.h>

void snail_flex_debug_off( void );
void snail_flex_debug_yyflex( void );
void snail_flex_debug_yylval( void );
void snail_flex_debug_yytext( void );
void snail_flex_debug_lines( void );

int snail_flex_current_line_number( void );
void snail_flex_set_current_line_number( ssize_t line );
int snail_flex_current_position( void );
void snail_flex_set_current_position( ssize_t pos );
const char *snail_flex_current_line( void );

void snail_flex_push_state( FILE *replace_yyin, cexception_t *ex );
void snail_flex_pop_state( void );

#endif
