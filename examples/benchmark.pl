use v5.20.0;
use strict;
use warnings;
no warnings 'once';

use Benchmark 'cmpthese';
use FindBin '$Bin';

use constant ITERATIONS => -3;

use lib "$Bin/lib";
use lib "$Bin/../lib";
use lib '/home/tai/src/p5/p5-lexical-accessor/lib';

eval 'require Local::Example::Core;   1' or warn $@;
eval 'require Local::Example::Plain;  1' or warn $@;
eval 'require Local::Example::Marlin; 1' or warn $@;
eval 'require Local::Example::Moo;    1' or warn $@;
eval 'require Local::Example::Moose;  1' or warn $@;

my ( %constructors, %accessors, %delegations, %combined );
for my $i ( @Local::Example::ALL ) {
	
	( my $implementation_name = $i ) =~ s/^Local::Example:://;

	my $person_class  = $i . "::Person";
	my $dev_class     = $i . "::Employee::Developer";
	
	$constructors{$implementation_name} = sub {
		for my $n ( 1 .. 100 ) {
			my $o1 = $person_class->new( name => 'Alice', age => $n );
			my $o2 = $dev_class->new( name => 'Carol', employee_id => $n );
		}
	};

	my $dev_object = $dev_class->new( name => 'Bob', employee_id => 1 );
	
	$accessors{$implementation_name} = sub {
		for my $n ( 1 .. 100 ) {
			my $name = $dev_object->name;
			my $id   = $dev_object->employee_id;
			my $lang = $dev_object->get_languages;
		}
	};
	
	$delegations{$implementation_name} = sub {
		for my $n ( 1 .. 100 ) {
			$dev_object->add_language( $_ )
				for qw/ Perl C C++ Ruby Python Haskell SQL Go Rust Java /;
			my @all = $dev_object->all_languages;
			@all == 10 or die;
			$dev_object->clear_languages;
		}
	};
	
	$combined{$implementation_name} = sub {
		for my $n ( 1 .. 25 ) {
			my $person = $person_class->new( name => 'Alice', age => $n );
			my $dev    = $dev_class->new( name => 'Carol', employee_id => $n, age => 42 );
			for my $n ( 1 .. 4 ) {
				$dev->age == 42 or die;
				$dev->name eq 'Carol' or die;
				$dev->add_language( $_ )
					for qw/ Perl C C++ Ruby Python Haskell SQL Go Rust Java /;
				my @all = $dev->all_languages;
				@all == 10 or die;
				$dev->clear_languages;
			}
		}
	};
}

say "[[ CONSTRUCTORS ]]";
cmpthese( ITERATIONS, \%constructors );
say "";

say "[[ ACCESSORS ]]";
cmpthese( ITERATIONS, \%accessors );
say "";

say "[[ DELEGATIONS ]]";
cmpthese( ITERATIONS, \%delegations );
say "";

say "[[ COMBINED ]]";
cmpthese( ITERATIONS, \%combined );
say "";

__END__
[[ CONSTRUCTORS ]]
         Rate  Plain  Moose    Moo Marlin   Core
Plain  1101/s     --   -52%   -55%   -64%   -77%
Moose  2274/s   107%     --    -6%   -26%   -52%
Moo    2423/s   120%     7%     --   -21%   -49%
Marlin 3061/s   178%    35%    26%     --   -35%
Core   4741/s   331%   108%    96%    55%     --

[[ ACCESSORS ]]
          Rate   Core  Moose  Plain    Moo Marlin
Core   16444/s     --    -9%   -11%   -43%   -50%
Moose  18056/s    10%     --    -3%   -38%   -45%
Plain  18561/s    13%     3%     --   -36%   -44%
Moo    29074/s    77%    61%    57%     --   -12%
Marlin 33091/s   101%    83%    78%    14%     --

[[ DELEGATIONS ]]
         Rate  Plain   Core  Moose    Moo Marlin
Plain  1597/s     --    -2%    -9%   -10%   -16%
Core   1622/s     2%     --    -7%    -9%   -15%
Moose  1746/s     9%     8%     --    -2%    -8%
Moo    1779/s    11%    10%     2%     --    -7%
Marlin 1907/s    19%    18%     9%     7%     --

[[ COMBINED ]]
         Rate  Plain   Core  Moose    Moo Marlin
Plain  1143/s     --   -17%   -17%   -21%   -27%
Core   1374/s    20%     --    -1%    -5%   -12%
Moose  1381/s    21%     1%     --    -4%   -12%
Moo    1441/s    26%     5%     4%     --    -8%
Marlin 1562/s    37%    14%    13%     8%     --
