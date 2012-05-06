/*--*-C-*------------------------------------------------------------------*\
* $Author$
* $Date$ 
* $Locker: saulius $
* $Revision$
* $Source: /home/saulius/src/compilers/hlc/RCS/hlc.flex,v $
* $State: Exp $
\*-------------------------------------------------------------------------*/

 /* %option yylineno */

%x	comment
%x	m2comment

DECIMAL_DIGIT  [0-9]
NAME	       [a-zA-Z_][a-zA-Z0-9_]*
INTEGER	       {DECIMAL_DIGIT}+
FIXED	       ({DECIMAL_DIGIT}+"."{DECIMAL_DIGIT}*)|("."{DECIMAL_DIGIT}+)
REAL           {FIXED}([eE]([-+]?)[0-9]+)?

 /* Double and single quoted strings */

DSTRING         \"(([^\"\n]|\\\")*)*\"
SSTRING         '(([^'\n]|\\')*)*'
STRING          {DSTRING}|{SSTRING}

UDSTRING        \"[^\"\n]*
USSTRING        '[^'\n]*
USTRING         {UDSTRING}|{USSTRING}

%{
/* exports: */
#include <snail_flex.h>

/* uses: */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <assert.h>
#include <common.h>
#include <yy.h>
#include <tnode.h>
#include <dnode.h>
#include <enode.h>
#include <snail_y.h>
#include <snail.tab.h>
#include <allocx.h>
#include <cexceptions.h>

typedef enum {
  SNAIL_FLEX_DEBUG_OFF = 0x00,
  SNAIL_FLEX_DEBUG_TEXT = 0x01,
  SNAIL_FLEX_DEBUG_YYLVAL = 0x02,
  SNAIL_FLEX_DEBUG_YYFLEX = 0x04,
  SNAIL_FLEX_DEBUG_LINES = 0x08,
} SNAIL_FLEX_DEBUG_FLAGS;

static int snail_flex_debug_flags = 0;

static char * currentLine = NULL;
static int currentLineLength = 0;
static int lineCnt = 1;
static int linePos, nextPos;

/* structure SNAIL_FLEX_STATE is used for creating a stack of states
   when processing included files */

typedef struct SNAIL_FLEX_STATE {
    YY_BUFFER_STATE flex_state;
    struct SNAIL_FLEX_STATE *next;
} SNAIL_FLEX_STATE;

static SNAIL_FLEX_STATE *new_snail_flex_state( YY_BUFFER_STATE flex_state,
                                               SNAIL_FLEX_STATE *next,
                                               cexception_t *ex )
{
    SNAIL_FLEX_STATE *state = callocx( sizeof(*state), 1, ex );
    state->flex_state = flex_state;
    state->next = next;

    return state;
}

static void delete_snail_flex_state( SNAIL_FLEX_STATE *state )
{
    freex( state );
}

static SNAIL_FLEX_STATE *Include_stack;

void snail_flex_push_state( FILE *replace_yyin, cexception_t *ex )
{
    SNAIL_FLEX_STATE *save_state =
	new_snail_flex_state( YY_CURRENT_BUFFER, Include_stack, ex );

    Include_stack = save_state;
    yy_switch_to_buffer( yy_create_buffer( replace_yyin, YY_BUF_SIZE ));
}

void snail_flex_pop_state( void )
{
    SNAIL_FLEX_STATE *top = Include_stack;
    if( top ) {
	Include_stack = top->next;
	yy_delete_buffer( YY_CURRENT_BUFFER );
	yy_switch_to_buffer( top->flex_state );
	delete_snail_flex_state( top );
    }
}

/* The following macros are used to save context for error reporting
routines (notably yyerror()). MARK remembers the start position of the
current token. If yacc fails, we know that it is this token that
caused an error, and can inform user about this.*/

#define COUNT_LINES lineCnt += yyleng;
#define MARK linePos = nextPos; nextPos += yyleng;
#define ADVANCE_MARK nextPos += yyleng
#define RESET_MARK linePos = nextPos = 0

static void storeCurrentLine( char *line, int length );

%}

%%

 /********* store line for better error reporting ***********/

^.*   { storeCurrentLine(yytext, yyleng); RESET_MARK; yyless(0); }
 \n+   COUNT_LINES; /** count lines **/

 /**************** eat up comments **************************/

"//".*
"#".*

"/*"			{ MARK; BEGIN(comment); }
<comment>^.*		{ RESET_MARK; storeCurrentLine(yytext, yyleng); yyless(0); }
<comment>\n+		{ COUNT_LINES; }
<comment>[^*\n]*	{ ADVANCE_MARK; }
<comment>"*"+[^*/\n]*	{ ADVANCE_MARK; }
<comment>"*"+"/"	{ ADVANCE_MARK; BEGIN(INITIAL); }

"(*"			{ MARK; BEGIN(m2comment); }
<m2comment>^.*		{ RESET_MARK; storeCurrentLine(yytext, yyleng); yyless(0); }
<m2comment>\n+		{ COUNT_LINES; }
<m2comment>[^*\n]*	{ ADVANCE_MARK; }
<m2comment>"*"+[^*)\n]*	{ ADVANCE_MARK; }
<m2comment>"*"+")"	{ ADVANCE_MARK; BEGIN(INITIAL); }

 /**************** eat up whitespace ************************/

[ \t]+			ADVANCE_MARK;

 /**************** multi-character tokens *********************/

":="                    { MARK; yylval.op = ':'/*OP_COPY*/; return __ASSIGN; }
"->"                    { MARK; yylval.op = ':'/*OP_COPY*/; return __ARROW; }
"="                     { MARK; yylval.op = ':'/*OP_COPY*/; return '='; }

"=>"                    { MARK; return __THICK_ARROW; }

"+="                    { MARK; yylval.s = "+"; return __ARITHM_ASSIGN; }
"-="                    { MARK; yylval.s = "-"; return __ARITHM_ASSIGN; }
"*="                    { MARK; yylval.s = "*"; return __ARITHM_ASSIGN; }
"/="                    { MARK; yylval.s = "/"; return __ARITHM_ASSIGN; }
"%="                    { MARK; yylval.s = "%"; return __ARITHM_ASSIGN; }
"|="                    { MARK; yylval.s = "|"; return __ARITHM_ASSIGN; }
"&="                    { MARK; yylval.s = "&"; return __ARITHM_ASSIGN; }
"^="                    { MARK; yylval.s = "^"; return __ARITHM_ASSIGN; }
"**="                   { MARK; yylval.s = "**"; return __ARITHM_ASSIGN; }
"&&="                   { MARK; yylval.s = "&&"; return __ARITHM_ASSIGN; }
"||="                   { MARK; yylval.s = "||"; return __ARITHM_ASSIGN; }

"_"			{ MARK; return '_'; }
"::"			{ MARK; return __COLON_COLON; }
"++"                    { MARK; return __INC; }
"--"                    { MARK; return __DEC; }
"&&"                    { MARK; return _AND; }
"||"                    { MARK; return _OR; }
"**"                    { MARK; return __STAR_STAR; }
">>"                    { MARK; return __LEFT_TO_RIGHT; }
"<<"                    { MARK; return __RIGHT_TO_LEFT; }
"%%"                    { MARK; return __DOUBLE_PERCENT; }
"??"                    { MARK; return __QQ; }
"..."                   { MARK; return __THREE_DOTS; }
".."                    { MARK; return __DOT_DOT; }

"!="			{ MARK; return __NE; }
"<="			{ MARK; return __LE; }
">="			{ MARK; return __GE; }
"=="                    { MARK; return __EQ; }

 /*********************** keywords ***************************/

addressof  { MARK; return _ADDRESSOF; }
and        { MARK; return _AND; }
array      { MARK; return _ARRAY; }
begin      { MARK; return '{'; }
blob       { MARK; return _BLOB; }
break      { MARK; return _BREAK; }
bytecode   { MARK; return _BYTECODE; }
catch      { MARK; return _CATCH; }
class      { MARK; return _CLASS; }
const      { MARK; return _CONST; }
continue   { MARK; return _CONTINUE; }
debug      { MARK; return _DEBUG; }
do         { MARK; return _DO; }
else       { MARK; return _ELSE; }
elsif      { MARK; return _ELSIF; }
end        { MARK; return '}'; }
enddo      { MARK; return _ENDDO; }
endif      { MARK; return _ENDIF; }
enum       { MARK; return _ENUM; }
exception  { MARK; return _EXCEPTION; }
for        { MARK; return _FOR; }
forward    { MARK; return _FORWARD; }
function   { MARK; return _FUNCTION; }
if         { MARK; return _IF; }
import     { MARK; return _IMPORT; }
include    { MARK; return _INCLUDE; }
inline     { MARK; return _INLINE; }
like       { MARK; return _LIKE; }
load       { MARK; return _LOAD; }
method     { MARK; return _METHOD; }
module     { MARK; return _MODULE; }
native     { MARK; return _NATIVE; }
new        { MARK; return _NEW; }
not        { MARK; return _NOT; }
null       { MARK; return _NULL; }
of         { MARK; return _OF; }
operator   { MARK; return _OPERATOR; }
or         { MARK; return _OR; }
pack       { MARK; return _PACK; }
package    { MARK; return _PACKAGE; }
procedure  { MARK; return _PROCEDURE; }
program    { MARK; return _PROGRAM; }
raise      { MARK; return _RAISE; }
readonly   { MARK; return _READONLY; }
reraise    { MARK; return _RERAISE; }
return     { MARK; return _RETURN; }
ro         { MARK; return _READONLY; }
shl        { MARK; return _SHL; }
shr        { MARK; return _SHR; }
sizeof     { MARK; return _SIZEOF; }
struct     { MARK; return _STRUCT; }
then       { MARK; return _THEN; }
to         { MARK; return _TO; }
try        { MARK; return _TRY; }
type       { MARK; return _TYPE; }
unpack     { MARK; return _UNPACK; }
use        { MARK; return _USE; }
var        { MARK; return _VAR; }
while      { MARK; return _WHILE; }

 /********************** identifiers *************************/

{NAME}			%{
                           MARK;
                           if( snail_flex_debug_flags &
			           SNAIL_FLEX_DEBUG_YYLVAL )
                               printf("yylval.s = %s\n", yytext);
                           yylval.s = strclone(yytext);
                           return __IDENTIFIER;
			%}

 /********************* literal constants *********************/

{INTEGER}".."		%{
                           yyless(strlen(yytext) - 2);
                           MARK;
                           yylval.s = strnclone(yytext, yyleng);
                           yylval.s = process_escapes(yylval.s);
			   return __INTEGER_CONST;
			%}

{INTEGER}		%{
                           MARK;
                           yylval.s = strnclone(yytext, yyleng);
                           yylval.s = process_escapes(yylval.s);
			   return __INTEGER_CONST;
			%}

"0x"{INTEGER}		%{
                           MARK;
                           yylval.s = strnclone(yytext, yyleng);
                           yylval.s = process_escapes(yylval.s);
			   return __INTEGER_CONST;
			%}

"0b"{INTEGER}		%{
                           MARK;
                           yylval.s = strnclone(yytext, yyleng);
                           yylval.s = process_escapes(yylval.s);
			   return __INTEGER_CONST;
			%}

"0o"{INTEGER}		%{
                           MARK;
                           yylval.s = strnclone(yytext, yyleng);
                           yylval.s = process_escapes(yylval.s);
			   return __INTEGER_CONST;
			%}

{REAL}			%{
                           MARK;
                           yylval.s = strnclone(yytext, yyleng);
                           yylval.s = process_escapes(yylval.s);
			   /* sscanf( yytext, "%lf", &yylval.r ); */
			   return __REAL_CONST;
			%}

 /************************* strings **********************************/

{STRING}		%{
                           MARK;
                           assert(yyleng > 1);
                           yylval.s = strnclone(yytext + 1, yyleng - 2);
                           yylval.s = process_escapes(yylval.s);
                           return __STRING_CONST;
			%}

({USTRING})$		%{
                           MARK;
                           assert(yyleng > 0);
                           yyerror("unterminated string");
                           yylval.s = yyleng > 1 ?
                                         strnclone(yytext + 1, yyleng - 2) :
                                         strclone("");
                           yylval.s = process_escapes(yylval.s);
                           return __STRING_CONST;
			%}

.			{ MARK; return yytext[0]; }

%%

void snail_flex_debug_off( void )
{
    snail_flex_debug_flags = 0;
#ifdef YYDEBUG
    yy_flex_debug = 0;
#endif
}

void snail_flex_debug_yyflex( void )
{
    snail_flex_debug_flags |= SNAIL_FLEX_DEBUG_YYFLEX;
#ifdef YYDEBUG
    yy_flex_debug = 1;
#endif
}

void snail_flex_debug_yylval( void )
{
    snail_flex_debug_flags |= SNAIL_FLEX_DEBUG_YYLVAL;
}

void snail_flex_debug_yytext( void )
{
    snail_flex_debug_flags |= SNAIL_FLEX_DEBUG_TEXT;
}

void snail_flex_debug_lines( void )
{
    snail_flex_debug_flags |= SNAIL_FLEX_DEBUG_LINES;
}

int snail_flex_current_line_number( void ) { return lineCnt; }
void snail_flex_set_current_line_number( ssize_t line ) { lineCnt = line; }
int snail_flex_current_position( void ) { return linePos+1; }
void snail_flex_set_current_position( ssize_t pos ) { linePos = pos - 1; }
const char *snail_flex_current_line( void ) { return currentLine; }

static void storeCurrentLine( char *line, int length )
{
   assert( line != NULL );
  
   #ifdef YYDEBUG
   if( snail_flex_debug_flags & SNAIL_FLEX_DEBUG_TEXT )
       printf("\t%3d : %s\n", lineCnt, line);
   if( snail_flex_debug_flags & SNAIL_FLEX_DEBUG_YYLVAL )
       printf("length = %d\nline = %s\n", length, line);
   #endif

   if( currentLineLength < length ) {
      currentLine = realloc(currentLine, length+1);
      assert(currentLine != NULL);
      currentLineLength = length;
   }
   strncpy(currentLine, line, length);
   currentLine[length] = '\0';
   if( snail_flex_debug_flags & SNAIL_FLEX_DEBUG_LINES ) {
       char *first_nonblank = currentLine;
       while( isspace( *first_nonblank )) first_nonblank++;
       if( *first_nonblank == '#' ) {
           snail_printf( NULL, "%s\n", currentLine );
       } else {
           snail_printf( NULL, "#\n# %s\n#\n", currentLine );
       }
   }
}
