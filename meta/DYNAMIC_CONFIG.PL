	if ( "$]" >= 5.011002 and "$]" < 5.037002 ) {
		$meta->{prereqs}{runtime}{'requires'}{'Lexical::Var'} = '0.010';
	}
	
	if ( "$]" < 5.010000 ) {
		$meta->{prereqs}{runtime}{'requires'}{'MRO::Compat'} = 0;
	}
