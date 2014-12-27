/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __TCODES_H
#define __TCODES_H

#include <run.h>

#if 0
#define INSTRUCTION_FN_ARGS instruction_t *code, cexception_t *ex
#else
#define INSTRUCTION_FN_ARGS void
#endif

#include "generated/byte_integer.h"
#include "generated/short_integer.h"
#include "generated/int_integer.h"
#include "generated/long_integer.h"
#include "generated/llong_integer.h"

#include "generated/float_float.h"
#include "generated/double_float.h"
#include "generated/ldouble_float.h"

#include "generated/byte_intfloat.h"
#include "generated/short_intfloat.h"
#include "generated/int_intfloat.h"
#include "generated/long_intfloat.h"
#include "generated/llong_intfloat.h"
#include "generated/float_intfloat.h"
#include "generated/double_intfloat.h"
#include "generated/ldouble_intfloat.h"

void tcode_add_table( char *table_name, void *library,
		      char **names, cexception_t *ex );

void *tcode_lookup( char *name );
void *tcode_lookup_library_opcode( char *lib_name, char *name );
char *tcode_lookup_name( void *funct );

/*
** Generic opcodes (opcodes that do not depend on particular stackcell
** field):
*/

int NOP( INSTRUCTION_FN_ARGS );
int DUP( INSTRUCTION_FN_ARGS );
int OVER( INSTRUCTION_FN_ARGS );
int SWAP( INSTRUCTION_FN_ARGS );
int DROP( INSTRUCTION_FN_ARGS );
int DROPN( INSTRUCTION_FN_ARGS );
int PDROP( INSTRUCTION_FN_ARGS );
int PDROPN( INSTRUCTION_FN_ARGS );
int ROT( INSTRUCTION_FN_ARGS );
int COPY( INSTRUCTION_FN_ARGS );

int OFFSET( INSTRUCTION_FN_ARGS );

int LD( INSTRUCTION_FN_ARGS );
int LDA( INSTRUCTION_FN_ARGS );
int ST( INSTRUCTION_FN_ARGS );
int LDG( INSTRUCTION_FN_ARGS );
int LDGA( INSTRUCTION_FN_ARGS );
int STG( INSTRUCTION_FN_ARGS );
int LDI( INSTRUCTION_FN_ARGS );
int STI( INSTRUCTION_FN_ARGS );
int GLDI( INSTRUCTION_FN_ARGS );
int GSTI( INSTRUCTION_FN_ARGS );

int EXIT( INSTRUCTION_FN_ARGS );

int NEWLINE( INSTRUCTION_FN_ARGS );
int SPACE( INSTRUCTION_FN_ARGS );

int ALLOC( INSTRUCTION_FN_ARGS );
int ALLOCVMT( INSTRUCTION_FN_ARGS );

int MKARRAY( INSTRUCTION_FN_ARGS );
int PMKARRAY( INSTRUCTION_FN_ARGS );
int CLONE( INSTRUCTION_FN_ARGS );
int MEMCPY( INSTRUCTION_FN_ARGS );

int ZLDC( INSTRUCTION_FN_ARGS );

int ENTER( INSTRUCTION_FN_ARGS );
int CALL( INSTRUCTION_FN_ARGS );
int ICALL( INSTRUCTION_FN_ARGS );
int VCALL( INSTRUCTION_FN_ARGS );
int DUMPVMT( INSTRUCTION_FN_ARGS );
int RTOR( INSTRUCTION_FN_ARGS );
int RFROMR( INSTRUCTION_FN_ARGS );
int TOR( INSTRUCTION_FN_ARGS );
int FROMR( INSTRUCTION_FN_ARGS );
int LDFN( INSTRUCTION_FN_ARGS );
int RET( INSTRUCTION_FN_ARGS );
int PUSHFRM( INSTRUCTION_FN_ARGS );
int POPFRM( INSTRUCTION_FN_ARGS );

int JMP( INSTRUCTION_FN_ARGS );

int ALLOCARGV( INSTRUCTION_FN_ARGS );
int ALLOCENV( INSTRUCTION_FN_ARGS );

/*
** Exception handling bytecode operators.
*/

int TRY( INSTRUCTION_FN_ARGS );
int RESTORE( INSTRUCTION_FN_ARGS );
int RAISEX( INSTRUCTION_FN_ARGS );
int RAISE( INSTRUCTION_FN_ARGS );
int RERAISE( INSTRUCTION_FN_ARGS );
int EXCEPTIONEQ( INSTRUCTION_FN_ARGS );
int ERRORMSG( INSTRUCTION_FN_ARGS );
int ERRORCODE( INSTRUCTION_FN_ARGS );
int EXCEPTIONID( INSTRUCTION_FN_ARGS );
int EXCEPTIONMODULE( INSTRUCTION_FN_ARGS );

/*
 * Standard input management bytecode operators -- to implement
 * 'whil(<>) { ... }' a-la Perl.
 */

int STDREAD( INSTRUCTION_FN_ARGS );

/*
** File management bytecode operators.
*/

int ALLOCSTDIO( INSTRUCTION_FN_ARGS );
int FDFILE( INSTRUCTION_FN_ARGS );

int FNAME( INSTRUCTION_FN_ARGS );
int FOPEN( INSTRUCTION_FN_ARGS );
int FCLOSE( INSTRUCTION_FN_ARGS );
int FREAD( INSTRUCTION_FN_ARGS );
int FWRITE( INSTRUCTION_FN_ARGS );
int FSEEK( INSTRUCTION_FN_ARGS );
int FTELL( INSTRUCTION_FN_ARGS );
int FEOF( INSTRUCTION_FN_ARGS );

/*
** Type conversion opcodes:
*/

int EXTEND( INSTRUCTION_FN_ARGS );
int HEXTEND( INSTRUCTION_FN_ARGS );
int LEXTEND( INSTRUCTION_FN_ARGS );

int LOWBYTE( INSTRUCTION_FN_ARGS );
int LOWSHORT( INSTRUCTION_FN_ARGS );
int LOWINT( INSTRUCTION_FN_ARGS );
int LOWLONG( INSTRUCTION_FN_ARGS );

int I2F( INSTRUCTION_FN_ARGS );
int L2F( INSTRUCTION_FN_ARGS );
int LL2F( INSTRUCTION_FN_ARGS );
//int LFLOOR( INSTRUCTION_FN_ARGS );

int I2D( INSTRUCTION_FN_ARGS );
int L2D( INSTRUCTION_FN_ARGS );
int LL2D( INSTRUCTION_FN_ARGS );
int F2D( INSTRUCTION_FN_ARGS );
//int LFLOORD( INSTRUCTION_FN_ARGS );

int I2LD( INSTRUCTION_FN_ARGS );
int L2LD( INSTRUCTION_FN_ARGS );
int LL2LD( INSTRUCTION_FN_ARGS );
int F2LD( INSTRUCTION_FN_ARGS );
int D2LD( INSTRUCTION_FN_ARGS );
//int LLFLOORLD( INSTRUCTION_FN_ARGS );

int DFLOAT( INSTRUCTION_FN_ARGS );
int LDDOUBLE( INSTRUCTION_FN_ARGS );

/*
** String opcodes:
*/

int SLDC( INSTRUCTION_FN_ARGS );
int SPRINT( INSTRUCTION_FN_ARGS );
int SFILEPRINT( INSTRUCTION_FN_ARGS );
int SFILESCAN( INSTRUCTION_FN_ARGS );
int SFILEREADLN( INSTRUCTION_FN_ARGS );

/*
** reference processing opcodes:
*/

int PLDZ( INSTRUCTION_FN_ARGS );

int PLD( INSTRUCTION_FN_ARGS );
int PLDA( INSTRUCTION_FN_ARGS );
int PST( INSTRUCTION_FN_ARGS );
int PLDG( INSTRUCTION_FN_ARGS );
int PLDGA( INSTRUCTION_FN_ARGS );
int PSTG( INSTRUCTION_FN_ARGS );
int PLDI( INSTRUCTION_FN_ARGS );
int PSTI( INSTRUCTION_FN_ARGS );

int PJZ( INSTRUCTION_FN_ARGS );
int PJNZ( INSTRUCTION_FN_ARGS );

/*
** Character processing opcodes that should be probably made from
** integer.cin.
*/

int CLDI( INSTRUCTION_FN_ARGS );
int CPRINT( INSTRUCTION_FN_ARGS );
int CLDCS( INSTRUCTION_FN_ARGS );

/*
** Experimental opcodes for efficiency tests:
*/

int INDEXVAR( INSTRUCTION_FN_ARGS );
int ILDXVAR( INSTRUCTION_FN_ARGS );
int PLDXVAR2( INSTRUCTION_FN_ARGS );

/*
** Reference comparisons:
*/

int PEQBOOL( INSTRUCTION_FN_ARGS );
int PNEBOOL( INSTRUCTION_FN_ARGS );
int PZBOOL( INSTRUCTION_FN_ARGS );

/*
** String processing:
*/

int STRCAT( INSTRUCTION_FN_ARGS );
int STRSTART( INSTRUCTION_FN_ARGS );
int STREND( INSTRUCTION_FN_ARGS );
int STREQ( INSTRUCTION_FN_ARGS );
int STRNE( INSTRUCTION_FN_ARGS );
int STRGT( INSTRUCTION_FN_ARGS );
int STRLT( INSTRUCTION_FN_ARGS );
int STRGE( INSTRUCTION_FN_ARGS );
int STRLE( INSTRUCTION_FN_ARGS );
int STRLEN( INSTRUCTION_FN_ARGS );
int STRINDEX( INSTRUCTION_FN_ARGS );
int STRCHR( INSTRUCTION_FN_ARGS );
int STRRCHR( INSTRUCTION_FN_ARGS );

/*
** Hash handling:
*/

int HASHADDR( INSTRUCTION_FN_ARGS );
int HASHVAL( INSTRUCTION_FN_ARGS );
int HASHPTR( INSTRUCTION_FN_ARGS );
int HASHDUMP( INSTRUCTION_FN_ARGS );

/*
** Exceptions and their tests
*/

int RAISE_TEST( INSTRUCTION_FN_ARGS );

/*
** Stack dump functions
*/

int ESPRINT( INSTRUCTION_FN_ARGS );

/*
 * String SPRINTF functions
 */

int SSPRINTF( INSTRUCTION_FN_ARGS );

/*
 * Ad-hoc bytecode operators; they should be moved into the .so
 * libraries and modules when dynamic library loading is implemented.
 */

int ASWAPW( INSTRUCTION_FN_ARGS );
int ASWAPD( INSTRUCTION_FN_ARGS );

/*
 * Stack management commands.
 */

int ZEROSTACK( INSTRUCTION_FN_ARGS );

/*
 * String packing and unpacking.
 */

int STRPACK( INSTRUCTION_FN_ARGS );
int STRPACKARRAY( INSTRUCTION_FN_ARGS );
int STRPACKMDARRAY( INSTRUCTION_FN_ARGS );
int STRUNPACK( INSTRUCTION_FN_ARGS );
int STRUNPACKARRAY( INSTRUCTION_FN_ARGS );
int STRUNPACKMDARRAY( INSTRUCTION_FN_ARGS );

int CHECKREF( INSTRUCTION_FN_ARGS );
int FILLARRAY( INSTRUCTION_FN_ARGS );
int FILLMDARRAY( INSTRUCTION_FN_ARGS );

int ASSERT( INSTRUCTION_FN_ARGS );

int DEBUG( INSTRUCTION_FN_ARGS );
int RTTIDUMP( INSTRUCTION_FN_ARGS );

/* Opcode used to implement 'foreach' loops on arrays and linked
   lists: */
int ADVANCE( INSTRUCTION_FN_ARGS );
int NEXT( INSTRUCTION_FN_ARGS );

#endif
