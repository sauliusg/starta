/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __OPCODES_H
#define __OPCODES_H

#include <run.h>

#if 0
#define INSTRUCTION_FN_ARGS instruction_t *code, cexception_t *ex
#else
#define INSTRUCTION_FN_ARGS void
#endif

extern istate_t *istate_ptr;

/*
 * Setting flags
 */

int STRICT( INSTRUCTION_FN_ARGS );

/*
** Type conversion opcodes:
*/

int UBEXTEND( INSTRUCTION_FN_ARGS );
int UEXTEND( INSTRUCTION_FN_ARGS );
int UHEXTEND( INSTRUCTION_FN_ARGS );
int ULEXTEND( INSTRUCTION_FN_ARGS );

/* Unsigned -> signed conversions: you can always convert an unsigned
   integer to a signed integre of larger size. */

int UB2S( INSTRUCTION_FN_ARGS );
int US2I( INSTRUCTION_FN_ARGS );
int UI2L( INSTRUCTION_FN_ARGS );
int UL2LL( INSTRUCTION_FN_ARGS );

#include "locally-generated/unsigned_ubyte.h"
#include "locally-generated/unsigned_ushort.h"
#include "locally-generated/unsigned_uint.h"
#include "locally-generated/unsigned_ulong.h"
#include "locally-generated/unsigned_ullong.h"

#endif
