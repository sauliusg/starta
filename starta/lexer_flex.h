/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __LEXER_FLEX_H
#define __LEXER_FLEX_H

#include <stdio.h>
#include <unistd.h> /* for ssize_t */
#include <cexceptions.h>

/* A typedef and a function that are needed outpside the lexer: */

typedef struct yy_buffer_state *YY_BUFFER_STATE;

void yy_delete_buffer( YY_BUFFER_STATE b );

YY_BUFFER_STATE yy_scan_string( const char *yy_str );

/* The compiler intefrace functions to control and query the lexer
   state: */

void compiler_flex_debug_off( void );
void compiler_flex_debug_yyflex( void );
void compiler_flex_debug_yylval( void );
void compiler_flex_debug_yytext( void );
void compiler_flex_debug_lines( void );

int compiler_flex_current_line_number( void );
void compiler_flex_set_current_line_number( ssize_t line );
int compiler_flex_current_position( void );
void compiler_flex_set_current_position( ssize_t pos );
const char *compiler_flex_current_line( void );

void compiler_flex_push_state( FILE *replace_yyin, cexception_t *ex );
void compiler_flex_pop_state( void );

void yyunget( void );

#endif
