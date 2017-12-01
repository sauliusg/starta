
function factorial( n )
{
    if( n > 0 ) return n * factorial( n - 1 );
    else return 1;
}

BEGIN {
    for( i = 0; i < 20; i++ ) {
        print factorial( i );
    }
}
