
/* external declarations specific to yacc */

#ifndef __YY_H
#define __YY_H

#include <stdio.h>
#include <stdarg.h>

extern FILE *yyin;

extern int yyparse( void );
extern int yyerror( char *message );

/* For testing of lexical analysers: */
extern int yylex( void );
extern char *yytext;

#ifdef YYDEBUG   
   extern int yydebug;
   extern int yy_flex_debug;
#endif

#endif

void yyerrorf( char *message, ... );
void yyverrorf( char *message, va_list ap );
