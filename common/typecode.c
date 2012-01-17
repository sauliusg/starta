/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

/* exports: */
#include <typecode.h>

/* uses: */
#include <typesize.h>
#include <byteorder.h>
#include <bytecode_file.h>
/*#include <bytecode_vector.h>*/
#include <assert.h>

size_t typecode_size( typecode_t tc )
{
    switch( tc ) {
        case TC_NONE:  return 0;

        case TC_WORD:  return 2;
        case TC_DWORD: return 4;
        case TC_QWORD: return 8;
        case TC_XWORD: return 16;

        case TC_BWORD:  return 2;
        case TC_BDWORD: return 4;
        case TC_BQWORD: return 8;
        case TC_BXWORD: return 16;

        case TC_LWORD:  return 2;
        case TC_LDWORD: return 4;
        case TC_LQWORD: return 8;
        case TC_LXWORD: return 16;

        case TC_BYTE:    return sizeof(byte);
        case TC_CHAR:    return sizeof(char);
        case TC_SHORT:   return sizeof(short);
        case TC_INT:     return sizeof(int);
        case TC_LONG:    return sizeof(long);
        case TC_LLONG:   return sizeof(llong);
        case TC_FLOAT:   return sizeof(float);
        case TC_DOUBLE:  return sizeof(double);
        case TC_LDOUBLE: return sizeof(ldouble);

        case TC_FAROFFSET: return sizeof(offset_t);
        case TC_FILE:      return sizeof(bytecode_file_hdr_t);
        // case TC_VECTOR:    return sizeof(bytecode_vector_hdr_t);
        case TC_VECTOR:    return sizeof(void*);
        case TC_PTR:       return sizeof(void*);

        case TC_PNUMBER:   return 0;

        default: assert( 0 );
    }
    assert( 0 );
    return 0;
}

size_t typecode_alignment( typecode_t tc )
{
    switch( tc ) {
        case TC_NONE:  return 0;

        case TC_WORD:
        case TC_DWORD:
        case TC_QWORD:
        case TC_XWORD:

        case TC_BWORD:
        case TC_BDWORD:
        case TC_BQWORD:
        case TC_BXWORD:

        case TC_LWORD:
        case TC_LDWORD:
        case TC_LQWORD:
        case TC_LXWORD: return 1;

        case TC_PNUMBER: return 1;

        case TC_BYTE:    return sizeof(byte);
        case TC_CHAR:    return sizeof(char);
        case TC_SHORT:   return sizeof(short);
        case TC_INT:     return sizeof(int);
        case TC_LONG:    return sizeof(long);
        case TC_LLONG:   return sizeof(llong);
        case TC_FLOAT:   return sizeof(float);
        case TC_DOUBLE:  return sizeof(double);
        case TC_LDOUBLE: return sizeof(ldouble);

        case TC_FAROFFSET: return 1;
        // case TC_FILE:      return sizeof(address_t);
        // case TC_VECTOR:    return sizeof(address_t);
        case TC_FILE:      return sizeof(void*);
        case TC_VECTOR:    return sizeof(void*);
        case TC_PTR:       return sizeof(void*);

        default: assert( 0 );
    }
    assert( 0 );
    return 0;
}


byteorder_t typecode_byteorder( typecode_t tc )
{
    switch( tc ) {
        case TC_NONE:
        case TC_WORD:
        case TC_DWORD:
        case TC_QWORD:
        case TC_XWORD: return DEFAULT_BYTEORDER;

        case TC_PNUMBER: return DEFAULT_BYTEORDER;

        case TC_BWORD:
        case TC_BDWORD:
        case TC_BQWORD:
        case TC_BXWORD: return BO_BIG_ENDIAN;

        case TC_LWORD:
        case TC_LDWORD:
        case TC_LQWORD:
        case TC_LXWORD: return BO_LITTLE_ENDIAN;

        case TC_BYTE:
        case TC_CHAR:
        case TC_SHORT:
        case TC_INT:
        case TC_LONG:
        case TC_LLONG:
        case TC_FLOAT:
        case TC_DOUBLE:
        case TC_LDOUBLE: return BO_MACHINE_ENDIAN;

        case TC_FAROFFSET: return DEFAULT_BYTEORDER;
        case TC_FILE:      return DEFAULT_BYTEORDER;
        case TC_VECTOR:    return DEFAULT_BYTEORDER;
        case TC_PTR:       return DEFAULT_BYTEORDER;

        default: assert( 0 );
    }
    assert( 0 );
    return 0;
}
