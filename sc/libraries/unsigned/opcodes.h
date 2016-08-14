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

extern istate_t *istate_ptr;

#include "locally-generated/unsigned_ushort.h"
#include "locally-generated/unsigned_uint.h"
#include "locally-generated/unsigned_ulong.h"
#include "locally-generated/unsigned_ullong.h"

#endif
