#!/usr/bin/perl -w

#
# Generate the reentr.c and reentr.h,
# and optionally also the relevant metaconfig units (-U option).
# 

use strict;
use Getopt::Std;
my %opts;
getopts('U', \%opts);

my %map = (
	   V => "void",
	   A => "char*",	# as an input argument
	   B => "char*",	# as an output argument 
	   C => "const char*",	# as a read-only input argument
	   I => "int",
	   L => "long",
	   W => "size_t",
	   H => "FILE**",
	   E => "int*",
	  );

# (See the definitions after __DATA__.)
# In func|inc|type|... a "S" means "type*", and a "R" means "type**".
# (The "types" are often structs, such as "struct passwd".)
#
# After the prototypes one can have |X=...|Y=... to define more types.
# A commonly used extra type is to define D to be equal to "type_data",
# for example "struct_hostent_data to" go with "struct hostent".
#
# Example #1: I_XSBWR means int  func_r(X, type, char*, size_t, type**)
# Example #2: S_SBIE  means type func_r(type, char*, int, int*)
# Example #3: S_CBI   means type func_r(const char*, char*, int)


die "reentr.h: $!" unless open(H, ">reentr.h");
select H;
print <<EOF;
/*
 *    reentr.h
 *
 *    Copyright (C) 2002, 2003, by Larry Wall and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 *  !!!!!!!   DO NOT EDIT THIS FILE   !!!!!!!
 *  This file is built by reentr.pl from data in reentr.pl.
 */

#ifndef REENTR_H
#define REENTR_H 

#ifdef USE_REENTRANT_API

#ifdef PERL_CORE
#   define PL_REENTRANT_RETINT PL_reentrant_retint
#endif

/* Deprecations: some platforms have the said reentrant interfaces
 * but they are declared obsolete and are not to be used.  Often this
 * means that the platform has threadsafed the interfaces (hopefully).
 * All this is OS version dependent, so we are of course fooling ourselves.
 * If you know of more deprecations on some platforms, please add your own. */

#ifdef __hpux
#   undef HAS_CRYPT_R
#   undef HAS_DRAND48_R
#   undef HAS_ENDGRENT_R
#   undef HAS_ENDPWENT_R
#   undef HAS_GETGRENT_R
#   undef HAS_GETPWENT_R
#   undef HAS_SETLOCALE_R
#   undef HAS_SRAND48_R
#   undef HAS_STRERROR_R
#   define NETDB_R_OBSOLETE
#endif

#if defined(__osf__) && defined(__alpha) /* Tru64 aka Digital UNIX */
#   undef HAS_CRYPT_R
#   undef HAS_STRERROR_R
#   define NETDB_R_OBSOLETE
#endif

#ifdef NETDB_R_OBSOLETE
#   undef HAS_ENDHOSTENT_R
#   undef HAS_ENDNETENT_R
#   undef HAS_ENDPROTOENT_R
#   undef HAS_ENDSERVENT_R
#   undef HAS_GETHOSTBYADDR_R
#   undef HAS_GETHOSTBYNAME_R
#   undef HAS_GETHOSTENT_R
#   undef HAS_GETNETBYADDR_R
#   undef HAS_GETNETBYNAME_R
#   undef HAS_GETNETENT_R
#   undef HAS_GETPROTOBYNAME_R
#   undef HAS_GETPROTOBYNUMBER_R
#   undef HAS_GETPROTOENT_R
#   undef HAS_GETSERVBYNAME_R
#   undef HAS_GETSERVBYPORT_R
#   undef HAS_GETSERVENT_R
#   undef HAS_SETHOSTENT_R
#   undef HAS_SETNETENT_R
#   undef HAS_SETPROTOENT_R
#   undef HAS_SETSERVENT_R
#endif

#ifdef I_PWD
#   include <pwd.h>
#endif
#ifdef I_GRP
#   include <grp.h>
#endif
#ifdef I_NETDB
#   include <netdb.h>
#endif
#ifdef I_STDLIB
#   include <stdlib.h>	/* drand48_data */
#endif
#ifdef I_CRYPT
#   ifdef I_CRYPT
#       include <crypt.h>
#   endif
#endif
#ifdef HAS_GETSPNAM_R
#   ifdef I_SHADOW
#       include <shadow.h>
#   endif
#endif

EOF

my %seenh; # the different prototypes signatures for this function
my %seena; # the different prototypes signatures for this function in order
my @seenf; # all the seen functions
my %seenp; # the different prototype signatures for all functions
my %seent; # the return type of this function
my %seens; # the type of this function's "S"
my %seend; # the type of this function's "D"
my %seenm; # all the types
my %seenu; # the length of the argument list of this function
my %seenr; # the return type of this function

while (<DATA>) { # Read in the protypes.
    next if /^\s+$/;
    chomp;
    my ($func, $hdr, $type, @p) = split(/\s*\|\s*/, $_, -1);
    my ($r,$u);
    # Split off the real function name and the argument list.
    ($func, $u) = split(' ', $func);
    $u = "V_V" unless $u;
    ($r, $u) = ($u =~ /^(.)_(.+)/);
    $seenu{$func} = $u eq 'V' ? 0 : length $u;
    $seenr{$func} = $r;
    my $FUNC = uc $func; # for output.
    push @seenf, $func;
    my %m = %map;
    if ($type) {
	$m{S} = "$type*";
	$m{R} = "$type**";
    }

    # Set any special mapping variables (like X=x_t)
    if (@p) {
	while ($p[-1] =~ /=/) {
	    my ($k, $v) = ($p[-1] =~ /^([A-Za-z])\s*=\s*(.*)/);
	    $m{$k} = $v;
	    pop @p;
	}
    }

    # If given the -U option open up the metaconfig unit for this function.
    if ($opts{U} && open(U, ">d_${func}_r.U"))  {
	select U;
    }

    if ($opts{U}) {
	# The metaconfig units needs prerequisite dependencies.
	my $prereqs  = '';
	my $prereqh  = '';
	my $prereqsh = '';
	if ($hdr ne 'stdio') { # There's no i_stdio.
	    $prereqs  = "i_$hdr";
	    $prereqh  = "$hdr.h";
	    $prereqsh = "\$$prereqs $prereqh";
	}
	my @prereq = qw(Inlibc Protochk Hasproto i_systypes usethreads);
	push @prereq, $prereqs;
        my $hdrs = "\$i_systypes sys/types.h define stdio.h $prereqsh";
        if ($hdr eq 'time') {
	    $hdrs .= " \$i_systime sys/time.h";
	    push @prereq, 'i_systime';
	}
	# Output the metaconfig unit header.
	print <<EOF;
?RCS: \$Id: d_${func}_r.U,v $
?RCS:
?RCS: Copyright (c) 2002,2003 Jarkko Hietaniemi
?RCS:
?RCS: You may distribute under the terms of either the GNU General Public
?RCS: License or the Artistic License, as specified in the README file.
?RCS:
?RCS: Generated by the reentr.pl from the Perl 5.8 distribution.
?RCS:
?MAKE:d_${func}_r ${func}_r_proto: @prereq
?MAKE:	-pick add \$@ %<
?S:d_${func}_r:
?S:	This variable conditionally defines the HAS_${FUNC}_R symbol,
?S:	which indicates to the C program that the ${func}_r()
?S:	routine is available.
?S:.
?S:${func}_r_proto:
?S:	This variable encodes the prototype of ${func}_r.
?S:	It is zero if d_${func}_r is undef, and one of the
?S:	REENTRANT_PROTO_T_ABC macros of reentr.h if d_${func}_r
?S:	is defined.
?S:.
?C:HAS_${FUNC}_R:
?C:	This symbol, if defined, indicates that the ${func}_r routine
?C:	is available to ${func} re-entrantly.
?C:.
?C:${FUNC}_R_PROTO:
?C:	This symbol encodes the prototype of ${func}_r.
?C:	It is zero if d_${func}_r is undef, and one of the
?C:	REENTRANT_PROTO_T_ABC macros of reentr.h if d_${func}_r
?C:	is defined.
?C:.
?H:#\$d_${func}_r HAS_${FUNC}_R	   /**/
?H:#define ${FUNC}_R_PROTO \$${func}_r_proto	   /**/
?H:.
?T:try hdrs d_${func}_r_proto
?LINT:set d_${func}_r
?LINT:set ${func}_r_proto
: see if ${func}_r exists
set ${func}_r d_${func}_r
eval \$inlibc
case "\$d_${func}_r" in
"\$define")
EOF
	print <<EOF;
	hdrs="$hdrs"
	case "\$d_${func}_r_proto:\$usethreads" in
	":define")	d_${func}_r_proto=define
		set d_${func}_r_proto ${func}_r \$hdrs
		eval \$hasproto ;;
	*)	;;
	esac
	case "\$d_${func}_r_proto" in
	define)
EOF
    }
    for my $p (@p) {
        my ($r, $a) = ($p =~ /^(.)_(.+)/);
	my $v = join(", ", map { $m{$_} } split '', $a);
	if ($opts{U}) {
	    print <<EOF ;
	case "\$${func}_r_proto" in
	''|0) try='$m{$r} ${func}_r($v);'
	./protochk "extern \$try" \$hdrs && ${func}_r_proto=$p ;;
	esac
EOF
        }
        $seenh{$func}->{$p}++;
        push @{$seena{$func}}, $p;
        $seenp{$p}++;
        $seent{$func} = $type;
        $seens{$func} = $m{S};
        $seend{$func} = $m{D};
	$seenm{$func} = \%m;
    }
    if ($opts{U}) {
	print <<EOF;
	case "\$${func}_r_proto" in
	''|0)	d_${func}_r=undef
 	        ${func}_r_proto=0
		echo "Disabling ${func}_r, cannot determine prototype." >&4 ;;
	* )	case "\$${func}_r_proto" in
		REENTRANT_PROTO*) ;;
		*) ${func}_r_proto="REENTRANT_PROTO_\$${func}_r_proto" ;;
		esac
		echo "Prototype: \$try" ;;
	esac
	;;
	*)	case "\$usethreads" in
		define) echo "${func}_r has no prototype, not using it." >&4 ;;
		esac
		d_${func}_r=undef
		${func}_r_proto=0
		;;
	esac
	;;
*)	${func}_r_proto=0
	;;
esac

EOF
	close(U);		    
    }
}

close DATA;

# Prepare to continue writing the reentr.h.

select H;

{
    # Write out all the known prototype signatures.
    my $i = 1;
    for my $p (sort keys %seenp) {
	print "#define REENTRANT_PROTO_${p}	${i}\n";
	$i++;
    }
}

my @struct; # REENTR struct members
my @size;   # struct member buffer size initialization code
my @init;   # struct member buffer initialization (malloc) code
my @free;   # struct member buffer release (free) code
my @wrap;   # the wrapper (foo(a) -> foo_r(a,...)) cpp code
my @define; # defines for optional features

sub ifprotomatch {
    my $FUNC = shift;
    join " || ", map { "${FUNC}_R_PROTO == REENTRANT_PROTO_$_" } @_;
}

sub pushssif {
    push @struct, @_;
    push @size, @_;
    push @init, @_;
    push @free, @_;
}

sub pushinitfree {
    my $func = shift;
    push @init, <<EOF;
	New(31338, PL_reentrant_buffer->_${func}_buffer, PL_reentrant_buffer->_${func}_size, char);
EOF
    push @free, <<EOF;
	Safefree(PL_reentrant_buffer->_${func}_buffer);
EOF
}

sub define {
    my ($n, $p, @F) = @_;
    my @H;
    my $H = uc $F[0];
    push @define, <<EOF;
/* The @F using \L$n? */

EOF
    my $GENFUNC;
    for my $func (@F) {
	my $FUNC = uc $func;
	my $HAS = "${FUNC}_R_HAS_$n";
	push @H, $HAS;
	my @h = grep { /$p/ } @{$seena{$func}};
	unless (defined $GENFUNC) {
	    $GENFUNC = $FUNC;
	    $GENFUNC =~ s/^GET//;
	}
	if (@h) {
	    push @define, "#if defined(HAS_${FUNC}_R) && (" . join(" || ", map { "${FUNC}_R_PROTO == REENTRANT_PROTO_$_" } @h) . ")\n";

	    push @define, <<EOF;
#   define $HAS
#else
#   undef  $HAS
#endif
EOF
        }
    }
    return if @F == 1;
    push @define, <<EOF;

/* Any of the @F using \L$n? */

EOF
    push @define, "#if (" . join(" || ", map { "defined($_)" } @H) . ")\n";
    push @define, <<EOF;
#   define USE_${GENFUNC}_$n
#else
#   undef  USE_${GENFUNC}_$n
#endif

EOF
}

define('BUFFER',  'B',
       qw(getgrent getgrgid getgrnam));

define('PTR',  'R',
       qw(getgrent getgrgid getgrnam));
define('PTR',  'R',
       qw(getpwent getpwnam getpwuid));
define('PTR',  'R',
       qw(getspent getspnam));

define('FPTR', 'H',
       qw(getgrent getgrgid getgrnam setgrent endgrent));
define('FPTR', 'H',
       qw(getpwent getpwnam getpwuid setpwent endpwent));

define('BUFFER',  'B',
       qw(getpwent getpwgid getpwnam));

define('PTR', 'R',
       qw(gethostent gethostbyaddr gethostbyname));
define('PTR', 'R',
       qw(getnetent getnetbyaddr getnetbyname));
define('PTR', 'R',
       qw(getprotoent getprotobyname getprotobynumber));
define('PTR', 'R',
       qw(getservent getservbyname getservbyport));

define('BUFFER', 'B',
       qw(gethostent gethostbyaddr gethostbyname));
define('BUFFER', 'B',
       qw(getnetent getnetbyaddr getnetbyname));
define('BUFFER', 'B',
       qw(getprotoent getprotobyname getprotobynumber));
define('BUFFER', 'B',
       qw(getservent getservbyname getservbyport));

define('ERRNO', 'E',
       qw(gethostent gethostbyaddr gethostbyname));
define('ERRNO', 'E',
       qw(getnetent getnetbyaddr getnetbyname));

# The following loop accumulates the "ssif" (struct, size, init, free)
# sections that declare the struct members (in reentr.h), and the buffer
# size initialization, buffer initialization (malloc), and buffer
# release (free) code (in reentr.c).
#
# The loop also contains a lot of intrinsic logic about groups of
# functions (since functions of certain kind operate the same way).

for my $func (@seenf) {
    my $FUNC = uc $func;
    my $ifdef = "#ifdef HAS_${FUNC}_R\n";
    my $endif = "#endif /* HAS_${FUNC}_R */\n";
    if (exists $seena{$func}) {
	my @p = @{$seena{$func}};
	if ($func =~ /^(asctime|ctime|getlogin|setlocale|strerror|ttyname)$/) {
	    pushssif $ifdef;
	    push @struct, <<EOF;
	char*	_${func}_buffer;
	size_t	_${func}_size;
EOF
	    push @size, <<EOF;
	PL_reentrant_buffer->_${func}_size = REENTRANTSMALLSIZE;
EOF
	    pushinitfree $func;
	    pushssif $endif;
	}
        elsif ($func =~ /^(crypt)$/) {
	    pushssif $ifdef;
	    push @struct, <<EOF;
#if CRYPT_R_PROTO == REENTRANT_PROTO_B_CCD
	$seend{$func} _${func}_data;
#else
	$seent{$func} _${func}_struct;
#endif
EOF
    	    push @init, <<EOF;
#if CRYPT_R_PROTO != REENTRANT_PROTO_B_CCD
	PL_reentrant_buffer->_${func}_struct_buffer = 0;
#endif
EOF
    	    push @free, <<EOF;
#if CRYPT_R_PROTO != REENTRANT_PROTO_B_CCD
	Safefree(PL_reentrant_buffer->_${func}_struct_buffer);
#endif
EOF
	    pushssif $endif;
	}
        elsif ($func =~ /^(drand48|gmtime|localtime)$/) {
	    pushssif $ifdef;
	    push @struct, <<EOF;
	$seent{$func} _${func}_struct;
EOF
	    if ($1 eq 'drand48') {
	        push @struct, <<EOF;
	double	_${func}_double;
EOF
	    }
	    pushssif $endif;
	}
        elsif ($func =~ /^random$/) {
	    pushssif $ifdef;
	    push @struct, <<EOF;
#   if RANDOM_R_PROTO != REENTRANT_PROTO_I_St
	$seent{$func} _${func}_struct;
#   endif
EOF
	    pushssif $endif;
	}
        elsif ($func =~ /^(getgrnam|getpwnam|getspnam)$/) {
	    pushssif $ifdef;
	    # 'genfunc' can be read either as 'generic' or 'genre',
	    # it represents a group of functions.
	    my $genfunc = $func;
	    $genfunc =~ s/nam/ent/g;
	    $genfunc =~ s/^get//;
	    my $GENFUNC = uc $genfunc;
	    push @struct, <<EOF;
	$seent{$func}	_${genfunc}_struct;
	char*	_${genfunc}_buffer;
	size_t	_${genfunc}_size;
EOF
            push @struct, <<EOF;
#   ifdef USE_${GENFUNC}_PTR
	$seent{$func}*	_${genfunc}_ptr;
#   endif
EOF
	    push @struct, <<EOF;
#   ifdef USE_${GENFUNC}_FPTR
	FILE*	_${genfunc}_fptr;
#   endif
EOF
	    push @init, <<EOF;
#   ifdef USE_${GENFUNC}_FPTR
	PL_reentrant_buffer->_${genfunc}_fptr = NULL;
#   endif
EOF
	    my $sc = $genfunc eq 'grent' ?
		    '_SC_GETGR_R_SIZE_MAX' : '_SC_GETPW_R_SIZE_MAX';
	    my $sz = "_${genfunc}_size";
	    push @size, <<EOF;
#   if defined(HAS_SYSCONF) && defined($sc) && !defined(__GLIBC__)
	PL_reentrant_buffer->$sz = sysconf($sc);
	if (PL_reentrant_buffer->$sz == -1)
		PL_reentrant_buffer->$sz = REENTRANTUSUALSIZE;
#   else
#       if defined(__osf__) && defined(__alpha) && defined(SIABUFSIZ)
	PL_reentrant_buffer->$sz = SIABUFSIZ;
#       else
#           ifdef __sgi
	PL_reentrant_buffer->$sz = BUFSIZ;
#           else
	PL_reentrant_buffer->$sz = REENTRANTUSUALSIZE;
#           endif
#       endif
#   endif 
EOF
	    pushinitfree $genfunc;
	    pushssif $endif;
	}
        elsif ($func =~ /^(gethostbyname|getnetbyname|getservbyname|getprotobyname)$/) {
	    pushssif $ifdef;
	    my $genfunc = $func;
	    $genfunc =~ s/byname/ent/;
	    $genfunc =~ s/^get//;
	    my $GENFUNC = uc $genfunc;
	    my $D = ifprotomatch($FUNC, grep {/D/} @p);
	    my $d = $seend{$func};
	    $d =~ s/\*$//; # snip: we need need the base type.
	    push @struct, <<EOF;
	$seent{$func}	_${genfunc}_struct;
#   if $D
	$d	_${genfunc}_data;
#   else
	char*	_${genfunc}_buffer;
	size_t	_${genfunc}_size;
#   endif
#   ifdef USE_${GENFUNC}_PTR
	$seent{$func}*	_${genfunc}_ptr;
#   endif
EOF
    	    push @struct, <<EOF;
#   ifdef USE_${GENFUNC}_ERRNO
	int	_${genfunc}_errno;
#   endif 
EOF
	    push @size, <<EOF;
#if   !($D)
	PL_reentrant_buffer->_${genfunc}_size = REENTRANTUSUALSIZE;
#endif
EOF
	    push @init, <<EOF;
#if   !($D)
	New(31338, PL_reentrant_buffer->_${genfunc}_buffer, PL_reentrant_buffer->_${genfunc}_size, char);
#endif
EOF
	    push @free, <<EOF;
#if   !($D)
	Safefree(PL_reentrant_buffer->_${genfunc}_buffer);
#endif
EOF
	    pushssif $endif;
	}
        elsif ($func =~ /^(readdir|readdir64)$/) {
	    pushssif $ifdef;
	    my $R = ifprotomatch($FUNC, grep {/R/} @p);
	    push @struct, <<EOF;
	$seent{$func}*	_${func}_struct;
	size_t	_${func}_size;
#   if $R
	$seent{$func}*	_${func}_ptr;
#   endif
EOF
	    push @size, <<EOF;
	/* This is the size Solaris recommends.
	 * (though we go static, should use pathconf() instead) */
	PL_reentrant_buffer->_${func}_size = sizeof($seent{$func}) + MAXPATHLEN + 1;
EOF
    	    push @init, <<EOF;
	PL_reentrant_buffer->_${func}_struct = ($seent{$func}*)safemalloc(PL_reentrant_buffer->_${func}_size);
EOF
	    push @free, <<EOF;
	Safefree(PL_reentrant_buffer->_${func}_struct);
EOF
	    pushssif $endif;
	}

	push @wrap, $ifdef;

	push @wrap, <<EOF;
#   undef $func
EOF

        # Write out what we have learned.
	
        my @v = 'a'..'z';
        my $v = join(", ", @v[0..$seenu{$func}-1]);
	for my $p (@p) {
	    my ($r, $a) = split '_', $p;
	    my $test = $r eq 'I' ? ' == 0' : '';
	    my $true  = 1;
	    my $genfunc = $func;
	    if ($genfunc =~ /^(?:get|set|end)(pw|gr|host|net|proto|serv|sp)/) {
		$genfunc = "${1}ent";
	    } elsif ($genfunc eq 'srand48') {
		$genfunc = "drand48";
	    }
	    my $b = $a;
	    my $w = '';
	    substr($b, 0, $seenu{$func}) = '';
	    if ($func =~ /^random$/) {
		$true = "PL_reentrant_buffer->_random_retval";
	    } elsif ($b =~ /R/) {
		$true = "PL_reentrant_buffer->_${genfunc}_ptr";
	    } elsif ($b =~ /T/ && $func eq 'drand48') {
		$true = "PL_reentrant_buffer->_${genfunc}_double";
	    } elsif ($b =~ /S/) {
		if ($func =~ /^readdir/) {
		    $true = "PL_reentrant_buffer->_${genfunc}_struct";
		} else {
		    $true = "&PL_reentrant_buffer->_${genfunc}_struct";
		}
	    } elsif ($b =~ /B/) {
		$true = "PL_reentrant_buffer->_${genfunc}_buffer";
	    }
	    if (length $b) {
		$w = join ", ",
		         map {
			     $_ eq 'R' ?
				 "&PL_reentrant_buffer->_${genfunc}_ptr" :
			     $_ eq 'E' ?
				 "&PL_reentrant_buffer->_${genfunc}_errno" :
			     $_ eq 'B' ?
				 "PL_reentrant_buffer->_${genfunc}_buffer" :
			     $_ =~ /^[WI]$/ ?
				 "PL_reentrant_buffer->_${genfunc}_size" :
			     $_ eq 'H' ?
				 "&PL_reentrant_buffer->_${genfunc}_fptr" :
			     $_ eq 'D' ?
				 "&PL_reentrant_buffer->_${genfunc}_data" :
			     $_ eq 'S' ?
				 ($func =~ /^readdir\d*$/ ?
				  "PL_reentrant_buffer->_${genfunc}_struct" :
				  $func =~ /^crypt$/ ?
				  "PL_reentrant_buffer->_${genfunc}_struct_buffer" :
				  "&PL_reentrant_buffer->_${genfunc}_struct") :
			     $_ eq 'T' && $func eq 'drand48' ?
				 "&PL_reentrant_buffer->_${genfunc}_double" :
			     $_ =~ /^[ilt]$/ && $func eq 'random' ?
				 "&PL_reentrant_buffer->_random_retval" :
				 $_
			 } split '', $b;
		$w = ", $w" if length $v;
	    }
	    my $call = "${func}_r($v$w)";
	    push @wrap, <<EOF;
#   if !defined($func) && ${FUNC}_R_PROTO == REENTRANT_PROTO_$p
EOF
	    if ($r eq 'V' || $r eq 'B') {
	        push @wrap, <<EOF;
#       define $func($v) $call
EOF
	    } else {
		if ($func =~ /^get/) {
		    my $rv = $v ? ", $v" : "";
		    if ($r eq 'I') {
			$call = qq[((PL_REENTRANT_RETINT = $call)$test ? $true : (((PL_REENTRANT_RETINT == ERANGE) || (errno == ERANGE)) ? ($seenm{$func}{$seenr{$func}})Perl_reentrant_retry("$func"$rv) : 0))];
			my $arg = join(", ", map { $seenm{$func}{substr($a,$_,1)}." ".$v[$_] } 0..$seenu{$func}-1);
			my $ret = $seenr{$func} eq 'V' ? "" : "return ";
			push @wrap, <<EOF;
#       ifdef PERL_CORE
#           define $func($v) $call
#       else
#           if defined(__GNUC__) && !defined(__STRICT_ANSI__) && !defined(PERL_GCC_PEDANTIC)
#               define $func($v) ({int PL_REENTRANT_RETINT; $call;})
#           else
#               define $func($v) Perl_reentr_$func($v)
                static $seenm{$func}{$seenr{$func}} Perl_reentr_$func($arg) {
                    dTHX;
                    int PL_REENTRANT_RETINT;
                    $ret$call;
                }
#           endif
#       endif
EOF
		    } else {
			push @wrap, <<EOF;
#       define $func($v) ($call$test ? $true : ((errno == ERANGE) ? Perl_reentrant_retry("$func"$rv) : 0))
EOF
                    }
		} else {
	        push @wrap, <<EOF;
#       define $func($v) ($call$test ? $true : 0)
EOF
		}
	    }
	    push @wrap, <<EOF;
#   endif
EOF
	}

	push @wrap, $endif, "\n";
    }
}

# New struct members added here to maintain binary compatibility with 5.8.0

if (exists $seena{crypt}) {
    push @struct, <<EOF;
#ifdef HAS_CRYPT_R
#if CRYPT_R_PROTO == REENTRANT_PROTO_B_CCD
#else
	struct crypt_data *_crypt_struct_buffer;
#endif
#endif /* HAS_CRYPT_R */
EOF
}

if (exists $seena{random}) {
    push @struct, <<EOF;
#ifdef HAS_RANDOM_R
#   if RANDOM_R_PROTO == REENTRANT_PROTO_I_iS
	int	_random_retval;
#   endif
#   if RANDOM_R_PROTO == REENTRANT_PROTO_I_lS
	long	_random_retval;
#   endif
#   if RANDOM_R_PROTO == REENTRANT_PROTO_I_St
	$seent{random} _random_struct;
	int32_t	_random_retval;
#   endif
#endif /* HAS_RANDOM_R */
EOF
}

if (exists $seena{srandom}) {
    push @struct, <<EOF;
#ifdef HAS_SRANDOM_R
	$seent{srandom} _srandom_struct;
#endif /* HAS_SRANDOM_R */
EOF
}


local $" = '';

print <<EOF;

/* Defines for indicating which special features are supported. */

@define
typedef struct {
@struct
    int dummy; /* cannot have empty structs */
} REENTR;

#endif /* USE_REENTRANT_API */

#endif
EOF

close(H);

die "reentr.inc: $!" unless open(H, ">reentr.inc");
select H;

local $" = '';

print <<EOF;
/*
 *    reentr.inc
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 *  !!!!!!!   DO NOT EDIT THIS FILE   !!!!!!!
 *  This file is built by reentrl.pl from data in reentr.pl.
 */

#ifndef REENTRINC
#define REENTRINC

#ifdef USE_REENTRANT_API

/* The reentrant wrappers. */

@wrap

#endif /* USE_REENTRANT_API */
 
#endif

EOF

close(H);

# Prepare to write the reentr.c.

die "reentr.c: $!" unless open(C, ">reentr.c");
select C;
print <<EOF;
/*
 *    reentr.c
 *
 *    Copyright (C) 2002, 2003, by Larry Wall and others
 *
 *    You may distribute under the terms of either the GNU General Public
 *    License or the Artistic License, as specified in the README file.
 *
 *  !!!!!!!   DO NOT EDIT THIS FILE   !!!!!!!
 *  This file is built by reentr.pl from data in reentr.pl.
 *
 * "Saruman," I said, standing away from him, "only one hand at a time can
 *  wield the One, and you know that well, so do not trouble to say we!"
 *
 * This file contains a collection of automatically created wrappers
 * (created by running reentr.pl) for reentrant (thread-safe) versions of
 * various library calls, such as getpwent_r.  The wrapping is done so
 * that other files like pp_sys.c calling those library functions need not
 * care about the differences between various platforms' idiosyncrasies
 * regarding these reentrant interfaces.  
 */

#include "EXTERN.h"
#define PERL_IN_REENTR_C
#include "perl.h"
#include "reentr.h"

void
Perl_reentrant_size(pTHX) {
#ifdef USE_REENTRANT_API
#define REENTRANTSMALLSIZE	 256	/* Make something up. */
#define REENTRANTUSUALSIZE	4096	/* Make something up. */
@size
#endif /* USE_REENTRANT_API */
}

void
Perl_reentrant_init(pTHX) {
#ifdef USE_REENTRANT_API
	New(31337, PL_reentrant_buffer, 1, REENTR);
	Perl_reentrant_size(aTHX);
@init
#endif /* USE_REENTRANT_API */
}

void
Perl_reentrant_free(pTHX) {
#ifdef USE_REENTRANT_API
@free
	Safefree(PL_reentrant_buffer);
#endif /* USE_REENTRANT_API */
}

void*
Perl_reentrant_retry(const char *f, ...)
{
    dTHX;
    void *retptr = NULL;
#ifdef USE_REENTRANT_API
#  if defined(USE_HOSTENT_BUFFER) || defined(USE_GRENT_BUFFER) || defined(USE_NETENT_BUFFER) || defined(USE_PWENT_BUFFER) || defined(USE_PROTOENT_BUFFER) || defined(USE_SERVENT_BUFFER)
    void *p0;
#  endif
#  if defined(USE_SERVENT_BUFFER)
    void *p1;
#  endif
#  if defined(USE_HOSTENT_BUFFER)
    size_t asize;
#  endif
#  if defined(USE_HOSTENT_BUFFER) || defined(USE_NETENT_BUFFER) || defined(USE_PROTOENT_BUFFER) || defined(USE_SERVENT_BUFFER)
    int anint;
#  endif
    va_list ap;

    va_start(ap, f);

    switch (PL_op->op_type) {
#ifdef USE_HOSTENT_BUFFER
    case OP_GHBYADDR:
    case OP_GHBYNAME:
    case OP_GHOSTENT:
	{
#ifdef PERL_REENTRANT_MAXSIZE
	    if (PL_reentrant_buffer->_hostent_size <=
		PERL_REENTRANT_MAXSIZE / 2)
#endif
	    {
		PL_reentrant_buffer->_hostent_size *= 2;
		Renew(PL_reentrant_buffer->_hostent_buffer,
		      PL_reentrant_buffer->_hostent_size, char);
		switch (PL_op->op_type) {
	        case OP_GHBYADDR:
		    p0    = va_arg(ap, void *);
		    asize = va_arg(ap, size_t);
		    anint  = va_arg(ap, int);
		    retptr = gethostbyaddr(p0, asize, anint); break;
	        case OP_GHBYNAME:
		    p0 = va_arg(ap, void *);
		    retptr = gethostbyname(p0); break;
	        case OP_GHOSTENT:
		    retptr = gethostent(); break;
	        default:
		    SETERRNO(ERANGE, LIB_INVARG);
		    break;
	        }
	    }
	}
	break;
#endif
#ifdef USE_GRENT_BUFFER
    case OP_GGRNAM:
    case OP_GGRGID:
    case OP_GGRENT:
	{
#ifdef PERL_REENTRANT_MAXSIZE
	    if (PL_reentrant_buffer->_grent_size <=
		PERL_REENTRANT_MAXSIZE / 2)
#endif
	    {
		Gid_t gid;
		PL_reentrant_buffer->_grent_size *= 2;
		Renew(PL_reentrant_buffer->_grent_buffer,
		      PL_reentrant_buffer->_grent_size, char);
		switch (PL_op->op_type) {
	        case OP_GGRNAM:
		    p0 = va_arg(ap, void *);
		    retptr = getgrnam(p0); break;
	        case OP_GGRGID:
#if Gid_t_size < INTSIZE
		    gid = (Gid_t)va_arg(ap, int);
#else
		    gid = va_arg(ap, Gid_t);
#endif
		    retptr = getgrgid(gid); break;
	        case OP_GGRENT:
		    retptr = getgrent(); break;
	        default:
		    SETERRNO(ERANGE, LIB_INVARG);
		    break;
	        }
	    }
	}
	break;
#endif
#ifdef USE_NETENT_BUFFER
    case OP_GNBYADDR:
    case OP_GNBYNAME:
    case OP_GNETENT:
	{
#ifdef PERL_REENTRANT_MAXSIZE
	    if (PL_reentrant_buffer->_netent_size <=
		PERL_REENTRANT_MAXSIZE / 2)
#endif
	    {
		Netdb_net_t net;
		PL_reentrant_buffer->_netent_size *= 2;
		Renew(PL_reentrant_buffer->_netent_buffer,
		      PL_reentrant_buffer->_netent_size, char);
		switch (PL_op->op_type) {
	        case OP_GNBYADDR:
		    net = va_arg(ap, Netdb_net_t);
		    anint = va_arg(ap, int);
		    retptr = getnetbyaddr(net, anint); break;
	        case OP_GNBYNAME:
		    p0 = va_arg(ap, void *);
		    retptr = getnetbyname(p0); break;
	        case OP_GNETENT:
		    retptr = getnetent(); break;
	        default:
		    SETERRNO(ERANGE, LIB_INVARG);
		    break;
	        }
	    }
	}
	break;
#endif
#ifdef USE_PWENT_BUFFER
    case OP_GPWNAM:
    case OP_GPWUID:
    case OP_GPWENT:
	{
#ifdef PERL_REENTRANT_MAXSIZE
	    if (PL_reentrant_buffer->_pwent_size <=
		PERL_REENTRANT_MAXSIZE / 2)
#endif
	    {
		Uid_t uid;
		PL_reentrant_buffer->_pwent_size *= 2;
		Renew(PL_reentrant_buffer->_pwent_buffer,
		      PL_reentrant_buffer->_pwent_size, char);
		switch (PL_op->op_type) {
	        case OP_GPWNAM:
		    p0 = va_arg(ap, void *);
		    retptr = getpwnam(p0); break;
	        case OP_GPWUID:
#if Uid_t_size < INTSIZE
		    uid = (Uid_t)va_arg(ap, int);
#else
		    uid = va_arg(ap, Uid_t);
#endif
		    retptr = getpwuid(uid); break;
	        case OP_GPWENT:
		    retptr = getpwent(); break;
	        default:
		    SETERRNO(ERANGE, LIB_INVARG);
		    break;
	        }
	    }
	}
	break;
#endif
#ifdef USE_PROTOENT_BUFFER
    case OP_GPBYNAME:
    case OP_GPBYNUMBER:
    case OP_GPROTOENT:
	{
#ifdef PERL_REENTRANT_MAXSIZE
	    if (PL_reentrant_buffer->_protoent_size <=
		PERL_REENTRANT_MAXSIZE / 2)
#endif
	    {
		PL_reentrant_buffer->_protoent_size *= 2;
		Renew(PL_reentrant_buffer->_protoent_buffer,
		      PL_reentrant_buffer->_protoent_size, char);
		switch (PL_op->op_type) {
	        case OP_GPBYNAME:
		    p0 = va_arg(ap, void *);
		    retptr = getprotobyname(p0); break;
	        case OP_GPBYNUMBER:
		    anint = va_arg(ap, int);
		    retptr = getprotobynumber(anint); break;
	        case OP_GPROTOENT:
		    retptr = getprotoent(); break;
	        default:
		    SETERRNO(ERANGE, LIB_INVARG);
		    break;
	        }
	    }
	}
	break;
#endif
#ifdef USE_SERVENT_BUFFER
    case OP_GSBYNAME:
    case OP_GSBYPORT:
    case OP_GSERVENT:
	{
#ifdef PERL_REENTRANT_MAXSIZE
	    if (PL_reentrant_buffer->_servent_size <=
		PERL_REENTRANT_MAXSIZE / 2)
#endif
	    {
		PL_reentrant_buffer->_servent_size *= 2;
		Renew(PL_reentrant_buffer->_servent_buffer,
		      PL_reentrant_buffer->_servent_size, char);
		switch (PL_op->op_type) {
	        case OP_GSBYNAME:
		    p0 = va_arg(ap, void *);
		    p1 = va_arg(ap, void *);
		    retptr = getservbyname(p0, p1); break;
	        case OP_GSBYPORT:
		    anint = va_arg(ap, int);
		    p0 = va_arg(ap, void *);
		    retptr = getservbyport(anint, p0); break;
	        case OP_GSERVENT:
		    retptr = getservent(); break;
	        default:
		    SETERRNO(ERANGE, LIB_INVARG);
		    break;
	        }
	    }
	}
	break;
#endif
    default:
	/* Not known how to retry, so just fail. */
	break;
    }

    va_end(ap);
#endif
    return retptr;
}

EOF

__DATA__
asctime B_S	|time	|const struct tm|B_SB|B_SBI|I_SB|I_SBI
crypt B_CC	|crypt	|struct crypt_data|B_CCS|B_CCD|D=CRYPTD*
ctermid	B_B	|stdio	|		|B_B
ctime B_S	|time	|const time_t	|B_SB|B_SBI|I_SB|I_SBI
drand48	d_V	|stdlib	|struct drand48_data	|I_ST|T=double*|d=double
endgrent	|grp	|		|I_H|V_H
endhostent	|netdb	|		|I_D|V_D|D=struct hostent_data*
endnetent	|netdb	|		|I_D|V_D|D=struct netent_data*
endprotoent	|netdb	|		|I_D|V_D|D=struct protoent_data*
endpwent	|pwd	|		|I_H|V_H
endservent	|netdb	|		|I_D|V_D|D=struct servent_data*
getgrent S_V	|grp	|struct group	|I_SBWR|I_SBIR|S_SBW|S_SBI|I_SBI|I_SBIH
getgrgid S_T	|grp	|struct group	|I_TSBWR|I_TSBIR|I_TSBI|S_TSBI|T=gid_t
getgrnam S_C	|grp	|struct group	|I_CSBWR|I_CSBIR|S_CBI|I_CSBI|S_CSBI
gethostbyaddr S_CWI	|netdb	|struct hostent	|I_CWISBWRE|S_CWISBWIE|S_CWISBIE|S_TWISBIE|S_CIISBIE|S_CSBIE|S_TSBIE|I_CWISD|I_CIISD|I_CII|I_TsISBWRE|D=struct hostent_data*|T=const void*|s=socklen_t
gethostbyname S_C	|netdb	|struct hostent	|I_CSBWRE|S_CSBIE|I_CSD|D=struct hostent_data*
gethostent S_V	|netdb	|struct hostent	|I_SBWRE|I_SBIE|S_SBIE|S_SBI|I_SBI|I_SD|D=struct hostent_data*
getlogin B_V	|unistd	|		|I_BW|I_BI|B_BW|B_BI
getnetbyaddr S_LI	|netdb	|struct netent	|I_UISBWRE|I_LISBI|S_TISBI|S_LISBI|I_TISD|I_LISD|I_IISD|I_uISBWRE|D=struct netent_data*|T=in_addr_t|U=unsigned long|u=uint32_t
getnetbyname S_C	|netdb	|struct netent	|I_CSBWRE|I_CSBI|S_CSBI|I_CSD|D=struct netent_data*
getnetent S_V	|netdb	|struct netent	|I_SBWRE|I_SBIE|S_SBIE|S_SBI|I_SBI|I_SD|D=struct netent_data*
getprotobyname S_C	|netdb	|struct protoent|I_CSBWR|S_CSBI|I_CSD|D=struct protoent_data*
getprotobynumber S_I	|netdb	|struct protoent|I_ISBWR|S_ISBI|I_ISD|D=struct protoent_data*
getprotoent S_V	|netdb	|struct protoent|I_SBWR|I_SBI|S_SBI|I_SD|D=struct protoent_data*
getpwent S_V	|pwd	|struct passwd	|I_SBWR|I_SBIR|S_SBW|S_SBI|I_SBI|I_SBIH
getpwnam S_C	|pwd	|struct passwd	|I_CSBWR|I_CSBIR|S_CSBI|I_CSBI
getpwuid S_T	|pwd	|struct passwd	|I_TSBWR|I_TSBIR|I_TSBI|S_TSBI|T=uid_t
getservbyname S_CC	|netdb	|struct servent	|I_CCSBWR|S_CCSBI|I_CCSD|D=struct servent_data*
getservbyport S_IC	|netdb	|struct servent	|I_ICSBWR|S_ICSBI|I_ICSD|D=struct servent_data*
getservent S_V	|netdb	|struct servent	|I_SBWR|I_SBI|S_SBI|I_SD|D=struct servent_data*
getspnam S_C	|shadow	|struct spwd	|I_CSBWR|S_CSBI
gmtime S_T	|time	|struct tm	|S_TS|I_TS|T=const time_t*
localtime S_T	|time	|struct tm	|S_TS|I_TS|T=const time_t*
random L_V	|stdlib	|struct random_data|I_iS|I_lS|I_St|i=int*|l=long*|t=int32_t*
readdir S_T	|dirent	|struct dirent	|I_TSR|I_TS|T=DIR*
readdir64 S_T	|dirent	|struct dirent64|I_TSR|I_TS|T=DIR*
setgrent	|grp	|		|I_H|V_H
sethostent V_I	|netdb	|		|I_ID|V_ID|D=struct hostent_data*
setlocale B_IC	|locale	|		|I_ICBI
setnetent V_I	|netdb	|		|I_ID|V_ID|D=struct netent_data*
setprotoent V_I	|netdb	|		|I_ID|V_ID|D=struct protoent_data*
setpwent	|pwd	|		|I_H|V_H
setservent V_I	|netdb	|		|I_ID|V_ID|D=struct servent_data*
srand48 V_L	|stdlib	|struct drand48_data	|I_LS
srandom	V_T	|stdlib	|struct random_data|I_TS|T=unsigned int
strerror B_I	|string	|		|I_IBW|I_IBI|B_IBW
tmpnam B_B	|stdio	|		|B_B
ttyname	B_I	|unistd	|		|I_IBW|I_IBI|B_IBI
