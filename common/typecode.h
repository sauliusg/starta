/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __TYPECODE_H
#define __TYPECODE_H

#include <stdlib.h>
#include <byteorder.h>

typedef enum {
  TC_UNKNOWN = 0,
  TC_NONE    = 1,

  TC_TRUE,
  TC_FALSE,

  TC_CHAR,
  TC_BYTE,

  TC_WORD,
  TC_DWORD,
  TC_QWORD,
  TC_XWORD,

  TC_LWORD,
  TC_LDWORD,
  TC_LQWORD,
  TC_LXWORD,

  TC_BWORD,
  TC_BDWORD,
  TC_BQWORD,
  TC_BXWORD,

  TC_SHORT,
  TC_INT,
  TC_LONG,
  TC_LLONG,
  TC_FLOAT,
  TC_DOUBLE,
  TC_LDOUBLE,
  TC_PTR,

  TC_PNUMBER,
      
  TC_FAROFFSET,

  TC_FILE,
  TC_VECTOR,

  last_typecode

} typecode_t;

size_t typecode_size( typecode_t tc );
size_t typecode_alignment( typecode_t tc );
byteorder_t typecode_byteorder( typecode_t tc );

#endif
