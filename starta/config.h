/*---------------------------------------------------------------------------*\
**$Author$
**$Date$ 
**$Revision$
**$URL$
\*---------------------------------------------------------------------------*/

#ifndef __CONFIG_H
#define __CONFIG_H

#define TRACE 1

/* Macros, defined on the older linux/i386 platform
** gcc --version
** 2.7.2.1
** uname -a
** Linux garnys 2.0.32 #4 Sun Jun 20 22:55:21 MEST 1999 i486 unknown
** #define __linux__ 1
** #define linux 1
** #define __i386__ 1
** #define __i386 1
** #define __GNUC_MINOR__ 7
** #define __i486__ 1
** #define i386 1
** #define __unix 1
** #define __unix__ 1
** #define __GNUC__ 2
** #define __linux 1
** #define __ELF__ 1
** #define unix 1
*/

/* macros. defined by the gcc on linux/i386 platform
** #define __linux__ 1 
** #define linux 1 
** #define __i386__ 1 
** #define __GNUC_MINOR__ 8 
** #define __i586__ 1 
** #define i386 1 
** #define i586 1 
** #define __unix 1 
** #define __unix__ 1 
** #define __GNUC__ 2 
** #define __linux 1 
** #define __ELF__ 1 
** #define unix 1 
*/

/* macros. defined by the gcc on irix/mips platform
** #define __LANGUAGE_C 1 
** #define __host_mips 1 
** #define SYSTYPE_SVR4 1 
** #define __MIPSEB 1 
** #define _LANGUAGE_C 1 
** #define __DSO__ 1 
** #define _MIPS_SZLONG 32 
** #define __mips__ 1 
** #define _SVR4_SOURCE 1 
** #define __mips 1 
** #define _LONGLONG 1 
** #define __host_mips__ 1 
** #define __SYSTYPE_SVR4 1 
** #define __SIZE_TYPE__ unsigned int 
** #define __GNUC_MINOR__ 95 
** #define __sgi 1 
** #define MIPSEB 1 
** #define __SYSTYPE_SVR4__ 1 
** #define _MIPS_SZINT 32 
** #define __PTRDIFF_TYPE__ int 
** #define host_mips 1 
** #define __CHAR_UNSIGNED__ 1 
** #define mips 1 
** #define _MODERN_C 1 
** #define _MIPS_SZPTR 32 
** #define __unix 1 
** #define sgi 1 
** #define __unix__ 1 
** #define _MIPSEB 1 
** #define _MIPS_FPSET 16 
** #define _SGI_SOURCE 1 
** #define __GNUC__ 2 
** #define __EXTENSIONS__ 1 
** #define _MIPS_ISA _MIPS_ISA_MIPS1 
** #define LANGUAGE_C 1 
** #define __sgi__ 1 
** #define _MIPS_SIM _MIPS_SIM_ABI32 
** #define __MIPSEB__ 1 
** #define unix 1 
*/

#ifdef AUTOCONFIG
#include <config/auto.h>
#else
/**/
#if defined(__GNUC__) && defined(__linux__) && defined(__i386__)
#if __GNUC__ <= 2 && __GNUC_MINOR__ <= 7
#include <config/gcc-linux-7.h>
#else
#include <config/gcc-linux.h>
#endif
#elif defined(__GNUC__) && defined(__sgi__) && defined(__mips__)
#include <config/gcc-irix.h>
#else
#include <config/tcc-linux.h>
#endif
/**/
#endif

#if _XOPEN_SOURCE >= 600 || _ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L
#define SSIZE_T_FORMAT "z"
#else
#define SSIZE_T_FORMAT SSIZE_FMT
#endif

#endif
