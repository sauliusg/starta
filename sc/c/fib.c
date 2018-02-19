#include <stdio.h>
#include <assert.h>

int fib( int );

int main( int argc, char *argv[] )
{
    int i;

    for( i = 0; i < 1000; i++ ) {
        assert( fib(20) == 6765 );
    }
    return 0;
}

int fib(int n)
{
    return n < 2 ? n : fib(n-1) + fib(n-2);
}
