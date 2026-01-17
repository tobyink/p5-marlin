use 5.008008;
use strict;
use warnings;

package Marlin::X::ToHash;

our $AUTHORITY = 'cpan:TOBYINK';
our $VERSION   = '0.016000';

use Marlin::Util          qw( true false );
use Types::Common         qw( -types );

use Marlin (
	-with       => 'Marlin::X',
	method_name => { isa => Str,     default => 'to_hash' },
	strict_args => { isa => Bool,    default => true },
);

use B                     ();
use Clone                 ();
use Eval::TypeTiny::CodeAccumulator;
use Scalar::Util          ();

sub BUILD {
	my $plugin = shift;
	if ( $plugin->marlin->isa('Marlin::Role') ) {
		Marlin::Util::_croak "Marlin::X::ToHash cannot be applied to roles";
	}
}

sub adjust_setup_steps {
	my $plugin = shift;
	my $steps  = shift;
	
	my $callback = sprintf '%s::%s', __PACKAGE__, 'setup_to_hash_method';
	push @$steps, $callback;
}

sub setup_to_hash_method {
	my $plugin = shift;
	my $marlin = shift;
	
	my $code = $plugin->_make_to_hash_method( $marlin );
	$marlin->export( $plugin->method_name, $code->compile );
	
	return $marlin;
}

sub _make_to_hash_method {
	my $plugin = shift;
	my $marlin = shift;
	
	my $code = Eval::TypeTiny::CodeAccumulator->new( description => 'to_hash' );
	$code->addf( 'sub {' );
	$code->increase_indent;
	$code->addf( 'my $self  = shift;' );
	$code->addf( InstanceOf->of( $marlin->this )->inline_assert('$self') );
	$code->addf( 'my $class = ref $self;' );

	{
		my $var = $code->add_variable( '$to_hash_plugin', \$plugin );
		$code->addf( 'if ( $class ne %s ) {', B::perlstring($marlin->this) );
		$code->increase_indent;
		$code->addf( 'my $child_marlin = %s->find_meta( $class ) or %s("$class is not a Marlin class");', ref($marlin), $marlin->_croaker );
		$code->addf( 'my $child_hasher = %s->_make_to_hash_method_for_child( $child_marlin );', $var );
		$code->addf( 'return $self->$child_hasher( @_ );' );
		$code->decrease_indent;
		$code->addf( '}' );
	}

	$code->addf( 'my %%args  = ( @_ == 1 and %s ) ? %%{+shift} : @_;', HashRef->inline_check('$_[0]') );
	$code->addf( 'my $hash = {};' );
	$code->addf( 'my $used = 0;' ) if $plugin->strict_args;
	$code->add_gap;
	
	$marlin->canonicalize_attributes;
	my @allowed;
	
	for my $attr ( @{ $marlin->attributes_with_inheritance } ) {
		
		if ( not exists $attr->{on_hash} ) {
			$attr->{on_hash} = ( $attr->{storage} ne 'PRIVATE' );
		}
		
		$code->addf( '{' );
		$code->increase_indent;
		$code->addf( 'my ( $value, $has_value );' );
		
		if ( $attr->{lazy} and $attr->{on_hash} =~ /:build/ ) {
			$code->add_line( $attr->inline_maybe_write_default('$self') );
		}
		
		my @aliases;
		@aliases = @{ $attr->{':Alias'}{alias} or [] } if $attr->{':Alias'};
		
		my $if = 'if';
		my $init_arg = exists( $attr->{init_arg} ) ? $attr->{init_arg} : $attr->{slot};
		push @allowed, $init_arg if defined $init_arg;
		
		if ( @aliases ) {
			$code->addf( 'if ( my @found = grep { exists $args{$_} } %s ) {',
				join( q[, ] => map { B::perlstring($_) } $init_arg, @aliases ) );
			$code->increase_indent;
			$code->addf( 'if ( @found > 1 ) {' );
			$code->increase_indent;
			$code->addf( 'shift @found;' );
			$code->addf( '%s("Superfluous %%s used for attribute \'%%s\': %%s" , @found==1 ? "alias" : "aliases", %s, join( q[, ], sort @found ) );', $attr->_croaker, B::perlstring($attr->{slot}) );
			$code->decrease_indent;
			$code->addf( '}' );
			$code->addf( '( $value, $has_value ) = ( $args{$found[0]}, !!1 );' );
			$code->addf( '$used++;' ) if $plugin->strict_args;
			$code->addf( 'undef $has_value unless defined $value;' ) if $attr->{undef_tolerant};
			$code->decrease_indent;
			$code->addf( '}' );
			$if = 'elsif';
			push @allowed, @aliases;
		}
		elsif ( defined $init_arg ) {
			$code->addf( 'if ( exists $args{%s} ) {', B::perlstring($init_arg) );
			$code->increase_indent;
			$code->addf( '( $value, $has_value ) = ( $args{%s}, !!1 );', B::perlstring($init_arg) );
			$code->addf( '$used++;' ) if $plugin->strict_args;
			$code->addf( 'undef $has_value unless defined $value;' ) if $attr->{undef_tolerant};
			$code->decrease_indent;
			$code->addf( '}' );
			$if = 'elsif';
		}
		
		if ( $attr->{on_hash} eq 1 or not exists $attr->{on_hash} ) {
			$code->addf( '%s ( %s ) {', $if, $attr->inline_predicate('$self') );
			$code->increase_indent;
			$code->addf( '( $value, $has_value ) = ( %s, !!1 );', $attr->inline_access('$self') );
			$code->decrease_indent;
			$code->addf( '}' );
		}
		elsif ( 'CODE' eq ref $attr->{on_hash} ) {
			my $var = $code->add_variable( $attr->make_var_name('hash_exporter'), \$attr->{on_hash} );
			$code->addf( '%s ( %s ) {', $if, $attr->inline_predicate('$self') );
			$code->increase_indent;
			$code->addf( '( $value, $has_value ) = ( scalar $self->%s( %s, %s ), !!1 );', $var, B::perlstring($attr->{slot}), $attr->inline_access('$self') );
			$code->decrease_indent;
			$code->addf( '}' );
		}
		elsif ( $attr->{on_hash} eq 0 or $attr->{on_hash} eq ':none' ) {
			# no clone
		}
		elsif ( !ref $attr->{on_hash} and $attr->{on_hash} =~ /:method\((.+?)\)/ ) {
			my $clone_method = $1;
			$code->addf( '%s ( %s and Scalar::Util::blessed( %s ) ) {', $if, $attr->inline_predicate('$self'), $attr->inline_access('$self') );
			$code->increase_indent;
			$code->addf( '( $value, $has_value ) = ( ( %s )->%s, !!1 );', $attr->inline_access('$self'), $clone_method );
			$code->decrease_indent;
			$code->addf( '}' );
		}
		elsif ( !ref $attr->{on_hash} and $attr->{on_hash} =~ /:method/ ) {
			$code->addf( '%s ( %s and Scalar::Util::blessed( %s ) ) {', $if, $attr->inline_predicate('$self'), $attr->inline_access('$self') );
			$code->increase_indent;
			$code->addf( '( $value, $has_value ) = ( ( %s )->to_hash, !!1 );', $attr->inline_access('$self') );
			$code->decrease_indent;
			$code->addf( '}' );
		}
		elsif ( !ref $attr->{on_hash} and $attr->{on_hash} =~ /:selfmethod\((.+?)\)/ ) {
			my $clone_method = $1;
			$code->addf( '%s ( %s ) {', $if, $attr->inline_predicate('$self') );
			$code->increase_indent;
			$code->addf( '( $value, $has_value ) = ( scalar $self->%s( %s, %s ), !!1 );', $clone_method, B::perlstring($attr->{slot}), $attr->inline_access('$self') );
			$code->decrease_indent;
			$code->addf( '}' );
		}
		elsif ( !ref $attr->{on_hash} and $attr->{on_hash} =~ /^[\W0-9]\w+$/ ) {
			$code->addf( '%s ( %s ) {', $if, $attr->inline_predicate('$self') );
			$code->increase_indent;
			$code->addf( '( $value, $has_value ) = ( scalar $self->%s( %s, %s ), !!1 );', $attr->{on_hash}, B::perlstring($attr->{slot}), $attr->inline_access('$self') );
			$code->decrease_indent;
			$code->addf( '}' );
		}
		elsif ( !ref $attr->{on_hash} and $attr->{on_hash} =~ /:deep/ ) {
			$code->addf( '%s ( %s ) {', $if, $attr->inline_predicate('$self') );
			$code->increase_indent;
			$code->addf( '( $value, $has_value ) = ( scalar Clone::clone( %s ), !!1 );', $attr->inline_access('$self') );
			$code->decrease_indent;
			$code->addf( '}' );
		}
		elsif ( !ref $attr->{on_hash} and $attr->{on_hash} =~ /:simple/ ) {
			$code->addf( '%s ( %s ) {', $if, $attr->inline_predicate('$self') );
			$code->increase_indent;
			$code->addf( '( $value, $has_value ) = ( %s, !!1 );', $attr->inline_access('$self') );
			$code->decrease_indent;
			$code->addf( '}' );
		}
		
		$code->addf( 'if ( $has_value ) {' );
		$code->increase_indent;
		do {
			local $attr->{storage} = 'HASH';
			if ( $attr->{on_hash} =~ /:key\((.+?)\)/) {
				my $new_key = $1;
				local $attr->{slot} = $new_key;
				$code->add_line( $attr->inline_access_w( '$hash', '$value' ) );
			}
			else {
				$code->add_line( $attr->inline_access_w( '$hash', '$value' ) );
			}
		};
		$code->decrease_indent;
		$code->addf( '}' );
		
		$code->decrease_indent;
		$code->addf( '}' );
		$code->add_gap;
	}
	
	if ( $plugin->strict_args ) {
		my $check = do {
			my $enum = Enum->of( @allowed );
			$enum->can( '_regexp' )
				? sprintf( '/\\A%s\\z/', $enum->_regexp )
				: $enum->inline_check( '$_' );
		};
		$code->addf( 'if ( keys( %%args ) > $used ) {' );
		$code->increase_indent;
		$code->addf( 'my @unknown = grep not( %s ), keys %%args;', $check );
		$code->addf( '%s("Unexpected keys in to_hash arguments: " . join( q[, ], sort @unknown ) ) if @unknown;', $marlin->_croaker );
		$code->decrease_indent;
		$code->add_line( '}' );
		$code->add_gap;
	}
	
	$code->addf('return $hash;');
	$code->decrease_indent;
	$code->addf( '}' );
	
	warn $code->code;
	
	return $code;
}

sub _make_to_hash_method_for_child {
	my $plugin = shift;
	my $marlin = shift;
	my $code = $plugin->_make_to_hash_method( $marlin );
	my $coderef = $code->compile;
	
	$marlin->export( $plugin->method_name, $coderef );
	return $coderef;
}

__PACKAGE__
__END__

