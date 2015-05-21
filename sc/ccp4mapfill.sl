#! /home/saulius/bin/sl --
//--*- C -*---------------------------------------------------------------------
//$Author: saulius $
//$Date: 2015-05-20 22:28:10 +0300 (Wed, 20 May 2015) $
//$Revision: 48 $
//$URL: svn+ssh://saulius-grazulis.lt/home/saulius/svn-repositories/sgem-xray/trunk/bin/ccp4mapfill.sl $
//------------------------------------------------------------------------------
//*
// Read a CCP4 map, fill it with dummy atoms.
//**

use * from std;

use * from Math;
use * from SOptions;
use * from SUsage;

use * from CCP4Map;
use * from UnitCell;
use * from PDB;
use * from Spacegroups;
use * from GNUrand48;

exception NULL_VECTOR_ERROR;

function symop_apply( double symop[][]; double xyz[] ) : array of double;
function symop_ortho_from_fract( float cell[] ) : array [][] of double;
function symop_fract_from_ortho( float[] cell ) : array [][] of double;

procedure print_map_header_remarks( CCP4MapHeader hdr );

var opt_seed = new OptionValue;
var opt_natoms = new OptionValue;
var opt_atoms_per_res = new OptionValue;
var opt_level = new OptionValue;
var opt_threshold = new OptionValue;
var opt_atom_density = new OptionValue;
var opt_atom_name = new OptionValue;
var opt_residue_name = new OptionValue;
var opt_randomise = new OptionValue;
var opt_max_iterations = new OptionValue;

//* Usage:
//     $0 --options ccp4.map
//
//* Options:
//
//  -S, --seed        12278  Use the provided seed for random number generator
//  -n, --natoms      10000  Output the specified number of atoms and stop
//  -s, --sigma-level   1.0  Put atoms to map regions above the given sigma
//  -t, --threshold     1.4  Put atoms above the specified density level
//  -d, --density      0.02  Specify density of atoms, in atoms/cubic Angstroem
//  -a, --atom-name       O  Use provided atom name (defaul: O)
//  -r, --residue-name  HOH  Use provided residue name (default: HOH)
//
//  -m, --max-iterations 10000000
//      Maximum number of iterations after which the program will bail out;
//      set --max-iterations to -1 for infinite looping.
//
//  -A, --atoms-per-residue 100
//      Use the specified number of atoms in one residue.
//
//  -R, --randomise, -R-,--dont-randomise
//      Pick random seed at the beginning of the work so that each identical
//      program invocation produces different results.
//
//  --help    print short usage message (this message) and exit.
//**

var options = 
[
 make_option( "-S", "--seed",         OT_INT    OptionType, opt_seed ),
 make_option( "-n", "--natoms",       OT_INT    OptionType, opt_natoms ),
 make_option( "-s", "--sigma-level",  OT_FLOAT  OptionType, opt_level ),
 make_option( "-t", "--threshold",    OT_FLOAT  OptionType, opt_threshold ),
 make_option( "-d", "--density",      OT_FLOAT  OptionType, opt_atom_density ),
 make_option( "-a", "--atom-name",    OT_STRING OptionType, opt_atom_name ),
 make_option( "-r", "--residue-name", OT_STRING OptionType, opt_residue_name ),

 make_option( "-m", "--max-iterations",
              OT_INT OptionType, opt_max_iterations ),

 make_option( "-A", "--atoms-per-residue",
              OT_INT OptionType, opt_atoms_per_res ),

 make_option( "-R", "--randomise",
              OT_BOOLEAN_TRUE  OptionType, opt_randomise ),

 make_option( "-R-","--dont-randomise",
              OT_BOOLEAN_FALSE OptionType, opt_randomise ),

 make_option( null, "--help", OT_FUNCTION OptionType, proc => SUsage::xusage ),
];

program ( argv : array of string; stdio : array of file )
begin

var stdout = stdio[1];
var stderr = stdio[2];

var files = get_options( argv, options );

// Default values and program parameters:

var seed: int = 12278;
var threshold: float;
var sigma_level: float = 1.0; // 1.0 sigma default level
var atom_density: float = 0.02;
var natoms: int;
var max_iterations: llong = 1000LL * 1000LL * 10LL;
var atoms_per_residue: int = 100;
var atom_type = " O";
var residue_name = "HOH";

// Process options and set variable that do not depend on the map
// density values:

if( opt_atom_name.count > 0 ) {
    atom_type = opt_atom_name.value;
    if( length(atom_type) == 2 ) {
        atom_type = " " _ atom_type;
    }
}

if( opt_residue_name.count > 0 ) {
    residue_name = opt_residue_name.value;
}

if( opt_atoms_per_res.count > 0 ) {
    atoms_per_residue = atoi( opt_atoms_per_res.value );
}

if( opt_atom_density.count > 0 ) {
    atom_density = strtof( opt_atom_density.value );
}

if( opt_level.count > 0 ) {
    sigma_level = strtof( opt_level.value );
}

if( opt_max_iterations.count > 0 ) {
    max_iterations = atoll( opt_max_iterations.value );
}

// Initialise random number generator as requested:

if( opt_randomise.value ) {
    var random = fload( "/dev/urandom", bytes => 8 );
    seed = unpack int( random, 0, "u4" );
} else {
    if( opt_seed.count > 0 ) {
        seed = strtoi( opt_seed.value );
    }
}

srand48( seed );

for( var argnr = 0; argnr <= last(files); argnr++ ) {
    try {
        var map = fload( files[argnr] );
        var hdr = CCP4Map::unpack_header( map );
        var raster = CCP4Map::unpack_raster( map, hdr );

        print_map_header_remarks( hdr );

        // Determine threshold from headers given in the map header

        if( opt_threshold.count > 0 ) {
            // user specified threshold overrides sigma level:
            threshold = strtof( opt_threshold.value );
        } else {
            threshold = sigma_level * hdr.rmsDeviation + hdr.meanDensity;
        }

        // calculate map average, sigma and the number of "high points"
        // (i.e. points above the declared threshold), from the raster:

        var llong nhigh;
        var double sum, sum2, value;
        for var i = 0 to last(raster) {
            for var j = 0 to last(raster[i]) {
                for var k = 0 to last(raster[i][j]) {
                   value = raster[i][j][k];
                   sum += value;
                   sum2 += value * value;
                   if( value > threshold@double ) {
                       nhigh ++;
                   }
                }
            }
        }

        // Now calculate various map statistics:

        var npoints = 
            hdr.crs[0]@llong * hdr.crs[1]@llong * hdr.crs[2]@llong;
        var average =
            sum / npoints@double;
        var sigma = 
            sqrt((sum2 - (sum*sum)/npoints@double)/(npoints - 1LL)@double);
        var high_percentage =
             nhigh@double / npoints@double;

        var xstep = hdr.cell[0]/hdr.xyzIntervals[0]@float;
        var ystep = hdr.cell[1]/hdr.xyzIntervals[1]@float;
        var zstep = hdr.cell[2]/hdr.xyzIntervals[2]@float;
        var voxel_volume =
            cell_volume( [ xstep, ystep, zstep,
                           hdr.cell[3], hdr.cell[4], hdr.cell[5] ] );
        var high_volume = voxel_volume * nhigh@double;

        . "REMARK calculated average   =", average;
        . "REMARK map reported average =", hdr.meanDensity;
        . "REMARK calculated average   =", sigma;
        . "REMARK map reported rms     =", hdr.rmsDeviation;
        . "REMARK cell volume          =",
              hdr.cell[0]@double * hdr.cell[1]@double * hdr.cell[2]@double;
        . "REMARK high volume          =", high_volume;
        . "REMARK random number seed   =", seed;

        // Determine computation parameters, those that might depend
        // on the density statistics of the map:

        if( opt_natoms.count > 0 ) {
            natoms = atoi( opt_natoms.value );
        } else {
            natoms = lowint( lround( atom_density@double * high_volume ));
        }

        . "REMARK requesting number of atoms:", natoms;

        // CRYST1 record should be printed after all remarks:

        print_cryst1( hdr.cell, sg_number => hdr.spaceGroup, Z => 1 );

        // generate atoms within the map:

        var xstart = hdr.start[hdr.mapX];
        var ystart = hdr.start[hdr.mapY];
        var zstart = hdr.start[hdr.mapZ];

        var xsize = hdr.crs[hdr.mapX];
        var ysize = hdr.crs[hdr.mapY];
        var zsize = hdr.crs[hdr.mapZ];

        var xintervals = hdr.xyzIntervals[0];
        var yintervals = hdr.xyzIntervals[1];
        var zintervals = hdr.xyzIntervals[2];

        var o2f = symop_fract_from_ortho( hdr.cell );
        if( !o2f ) {
            raise NULL_VECTOR_ERROR("NULL f2o symop");
        }

        var f2o = symop_ortho_from_fract( hdr.cell );
        if( !f2o ) {
            raise NULL_VECTOR_ERROR("NULL f2o symop");
        }

        var atom_number, residue_number : int;

        var int n = 0;
        var llong niterations = 0;
        while( n < natoms ) {
            var rx, ry, rz : double = drand48(), drand48(), drand48();
            var gx, gy, gz : double =
                rx * (xsize - 1)@double,
                ry * (ysize - 1)@double,
                rz * (zsize - 1)@double;
            var ix, iy, iz = lround( gx ), lround( gy ), lround( gz );
            var fx, fy, fz : double =
                (gx + xstart@double) / (xintervals)@double,
                (gy + ystart@double) / (yintervals)@double,
                (gz + zstart@double) / (zintervals)@double;

            if( ix < 0L || ix > llast(raster) ) {
                raise ArrayOverflowException
                    ( "ix value "+("%d"%%ix)+" is out of range");
            }
            if( iy < 0L || iy > llast(raster) ) {
                raise ArrayOverflowException
                    ( "iy value "+("%d"%%iy)+" is out of range");
            }
            if( iz < 0L || iz > llast(raster) ) {
                raise ArrayOverflowException
                    ( "iz value "+("%d"%%iz)+" is out of range");
            }

            if( raster[ix][iy][iz] > threshold ) {
                n++;
                residue_number = n / atoms_per_residue + 1;
                var atom_name =
                    atom_type _ "%d" %% n % atoms_per_residue;
                var xyz = symop_apply( f2o, [fx, fy, fz] );
                print_atom( xyz, residue_number, n, atom_name => atom_name,
                            residue_name => residue_name );
            }
            niterations ++;
            if( niterations > max_iterations && max_iterations > -1LL ) {
                raise MAX_ITERATIONS_REACHED
                    ( "could not generate %d atoms " %% natoms _
                      "after %lld iterations"%% max_iterations );
            }
        }

    }
    catch( var message : string ) {
        <stderr> << argv[0] _ ": " _ files[argnr] _ ": " _ message _ "\n";
    }

    do . "" if argnr < last(files);
}

end; // main program

procedure print_map_header_remarks( CCP4MapHeader hdr )
{
    . "REMARK future words:", length(hdr.future);

    . "REMARK skew flag", hdr.skewFlag;
    for( var i = 0; i < length(hdr.skewMatrix); i ++ ) {
        < "REMARK skew matrix ";
        for( var j = 0; j < length(hdr.skewMatrix[i]); j ++ ) {
            < hdr.skewMatrix[i][j];
            < " ";
        }
        . "";
    }

    < "REMARK skew transl ";
    for( var i = 0; i < length(hdr.skewTranslation); i++ ) {
        < hdr.skewTranslation[i];
        < " ";
    }
    . "";

    . "REMARK machine stamp:", "0x%04X" %% 
          hdr.machineStamp[1] << 8 | hdr.machineStamp[0];

    for( var i = 0;
         i < (hdr.labelNr < length(hdr.labels) ?
              hdr.labelNr : length(hdr.labels));
         i ++ ) {
        . "REMARK MAP LABEL[", i, "]", hdr.labels[i];
    }

    . "REMARK MAP MODE", hdr.mode;
    . "REMARK xsize, ysize, zsize =", 
          hdr.xyzIntervals[0], hdr.xyzIntervals[1], hdr.xyzIntervals[2];
    . "REMARK cstart, rstart, sstart =",
          hdr.start[0], hdr.start[1], hdr.start[2];
    . "REMARK symop bytes", hdr.symmetryBytes;
}

function matrix3x3_times_vector( double m[][]; double v[] ) : array of double
{
    return
        [
         m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2],
         m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2],
         m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2]
        ];
}

function symop_apply( double symop[][]; double vector[] ) : array of double
{
    if( !vector ) {
        raise NULL_VECTOR_ERROR("NULL parameter in symop_apply");
    }

    var v = matrix3x3_times_vector( symop, vector );

    if( !v ) {
        raise NULL_VECTOR_ERROR("NULL vector v in symop_apply");
    }

    return [
	    v[0] + symop[3][0],
	    v[1] + symop[3][1],
	    v[2] + symop[3][2]
	   ];
}

function symop_fract_from_ortho( float[] cell ) : array [][] of double
{
    var a, b, c, alpha, beta, gamma : double;
    var sg, ca, cb, cg : double;

    a, b, c = cell[0], cell[1], cell[2];
    alpha = Pi * cell[3]@double / 180.0D;
    beta  = Pi * cell[4]@double / 180.0D;
    gamma = Pi * cell[5]@double / 180.0D;

    ca = cos( alpha );
    cb = cos( beta );
    cg = cos( gamma );

    sg = sin( gamma );

    var ctg = cg/sg;
    var D = sqrt(sg*sg - cb*cb - ca*ca + 2.0D*ca*cb*cg);

    return [
        [ 1.0D/a, -(1.D/a)*ctg,  (ca*cg-cb)/(a*D)    ],
        [   0.0D,   1.D/(b*sg), -(ca-cb*cg)/(b*D*sg) ],
        [   0.0D,   0.0D,             sg/(c*D) ],
        [   0.0D,   0.0D, 0.0D ] // zero translation vector
    ];
}

function symop_ortho_from_fract( float cell[] ) : array [][] of double
{
    var a, b, c, alpha, beta, gamma : double;
    var sg, ca, cb, cg : double;

    a, b, c = cell[0], cell[1], cell[2];
    alpha = Pi * cell[3]@double / 180.0D;
    beta  = Pi * cell[4]@double / 180.0D;
    gamma = Pi * cell[5]@double / 180.0D;

    ca = cos( alpha );
    cb = cos( beta );
    cg = cos( gamma );

    sg = sin( gamma );

    return [
        [ a,    b*cg, c*cb            ],
        [ 0.0D, b*sg, c*(ca-cb*cg)/sg ],
        [ 0.0D, 0.0D, c*sqrt(sg*sg-ca*ca-cb*cb+2.0D*ca*cb*cg)/sg ],
        [ 0.0D, 0.0D, 0.0D ] // zero translation vector
    ];
}
