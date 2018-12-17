# parseAnswerSet.pm
#
# Martin Brain
# mjb@cs.bath.ac.uk
# 03/03/09
#
# Collecting all of the parsing code needed into one place.

sub parseAnswerSet {
   my $fileHandle = shift;
   my $line;

    while ($line = <$fileHandle>) {
      if ($line =~ /^Answer: (\d+)/) {
	$line = <$fileHandle>;
	if ($line =~ /^Stable Model: (.*)\n/) {        # smodels style
	  $line = $1;
	} elsif ($line =~ /^ Answer set: (.*)\n/) {    # cmodels / sup style
	  $line = $1
	} else {                                       # clasp style
	  chomp $line;
	}
	return ("Answer Set",$line);

      } elsif ($line =~ /^Optimization: (\d+)/) {      # clasp style
	  return ("Value",$1);

      } elsif (($line =~ /^Time *: *(.*)\n$/) or       # clasp style
	       ($line =~ /^Duration: (.*)\n$/) or      # smodels style
	       ($line =~ /^CPU time *: *(.*)\n$/) or   
	       ($line =~ /User time .*: (.*)\n$/) or   # GNU time -v
	       ($line =~ /^user(.*)\n/) or             # bash time
	       ($line =~ /Total time: (.*)\n/)) {      # platypus style
	  return ("Time",$1);


      } elsif (($line =~ /signal 24/) or
	       ($line =~ /CPU time limit exceeded/) or
	       ($line =~ /time: command terminated abnormally./)) {
	return ("Time Out","");
	
	
      } elsif (($line =~ /signal 11/) or
	       ($line =~ /out of memory/) or
	       ($line =~ /std::bad_alloc/)) {          # clasp style
            return ("Memory Out\n","");
	  }
    }

   return ("End","");

}

1;
