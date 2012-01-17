/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __OPTYPE_H
#define __OPTYPE_H

typedef enum OP_TYPE {
    OP_UNKNOWN = 256,
    OP_NOP,

    OP_COPY,
    OP_REF_COPY,
    OP_VAL_COPY,
    OP_CAT,
    OP_ADD,
    OP_SUB,
    OP_MUL,
    OP_DIV,
    OP_MOD,
    OP_REM,
    OP_POW,
    OP_INC,
    OP_DEC,
    OP_PRE_INC,
    OP_PRE_DEC,
    OP_POST_INC,
    OP_POST_DEC,
    OP_NEGATE,

    OP_BITAND,
    OP_BITOR,
    OP_BITXOR,
    OP_BITNOT,

    OP_AND,
    OP_AND_ALSO,
    OP_OR,
    OP_OR_ALSO,
    OP_XOR,
    OP_NOT,

    OP_EQ,
    OP_NE,
    OP_LT,
    OP_GT,
    OP_LE,
    OP_GE,
    OP_CMP,
    OP_POINTER_EQ,
    OP_POINTER_NE,

    OP_IN,
    OP_MATCH,

    OP_FIELD_ACCESS,
    OP_TYPECAST,
    OP_TYPECONVERT,
    OP_INDEX,
    OP_DEREF,
    OP_ADDRESSOF,
    OP_NEW,

    OP_INPUT,
    OP_OUTPUT,
    OP_PRINT,
    OP_SCAN,
    OP_PRINTSP,
    OP_SCANSP,
    OP_PRINTNL,
    OP_LEFT_TO_RIGHT_IO,
    OP_RIGHT_TO_LEFT_IO,

    last_OP_TYPE
} OP_TYPE;

#endif
