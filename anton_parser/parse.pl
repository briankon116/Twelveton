#!/usr/bin/perl -w -I ./lib/

## Copyright (C) 2010 Martin Brain and Georg Boenn
## 
## This program is free software; you can redistribute it and/or
## modify it under the terms of the GNU General Public License
## as published by the Free Software Foundation; either version 2
## of the License, or (at your option) any later version.
## 
## This program is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
## 
## You should have received a copy of the GNU General Public License
## along with this program; if not, write to the Free Software
## Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  
## 02110-1301, USA.


#
# Martin Brain
# 13/12/06
# mjb@cs.bath.ac.uk
#
# A small script to convert answer sets into either human readable or csound notation

use strict;
use Getopt::Long;
use parseAnswerSet;

## Declare variables

# Flags
my $help;
my $output;
my $template;
my $fundamental;
my $transpose;
my $validOutput;
#my @validOutputs = ("human", "example", "csound", "csound-advanced", "lilypond", "graphviz");
my @validOutputs = ("human", "example", "csound", "lilypond", "graphviz");

# Data picked up from the answer set
my $part;
my $offset;
my $mode;
my $style;

# Counters
my $i;
my $t;
my $type;
my $line;
my $timeLimit;
my $pieceTimeLimit;
my $found;
my $defaultAmplitude;
my $answerSets;

# Lilypond variables
my $numvoices;
my $voicecount = 1;
my $layerLimit = 26 * 26;
my $modeName;
my @noteNamesLilypond = ( " c", "cis", " d","ees"," e"," f","fis"," g","aes"," a","bes"," b" );
my $tripletOpen = 0;
my $treeTimeSignature;
my %lastNode;
my $endOfBar;

# Csound advanced variables
my $max;
my $min;
my $gain;
my $duration;
my $defaultNoteDuration;
my $defaultMeasureDuration;
my $amplitude;
my $meterMultiplier;

# GraphViz variables
my $tree;
my $maxExpansion;
my $depth;
my $node;
my %nodeDuration;
my $displayNotes;
my $displayLinks;
my %possibleChord;
my $key;

# Other variables
my $count;
my @noteNames = ( " C", "C#", " D","D#"," E"," F","F#"," G","G#"," A","A#"," B" );


# A helper function for the more advanced csound output
# scale value x with known range between x_min and x_max
# into new range between new_min and new_max
sub scale {
  my $x = shift;
  my $new_min = shift;
  my $new_max = shift;
  my $x_min = shift;
  my $x_max = shift;

  return ( ($new_max - $new_min) * ($x - $x_min) / ($x_max - $x_min) + $new_min );
}

sub csoundAmplitude {
  my $line = shift;
  my $defaultAmplitude = shift;
  my $emphasis = shift;
  my $meterMultiplier = shift;
  my $part = 2;


  while ($line =~ /part\($part\)/) { ++$part; }
  --$part;

  return $defaultAmplitude - (10 * log($part)/log(10)) + ($emphasis * $meterMultiplier);
}

sub csoundFormat {
  my $note = shift;
  my $offset = shift;
  my $transpose = shift;
  my $amplitude = shift;

  print " ";
  print int(((($note + $offset) - 25) / 12) + (8 + $transpose));
  print ".";
  printf("%02d",int((($note + $offset) - 25) % 12));
  print " $amplitude\n";

  return;
}

sub isUsingRhythm {
  $line = shift;

  return ($line =~ /rhythm\(1\)/);
}

sub isUsingChords {
  $line = shift;

  return ($line =~ /chordal\(1\)/);
}

sub graphvizWalkFareyTree {
  my $line = shift;
  my $tree = shift;
  my $maxExpansion = shift;
  my $depth = shift;
  my $node = shift;
  my $duration = shift;
  my $current;
  my $shape;
  my $strength;
  my $strengthMax;
  my $expansion;
  my $i;


  # Print node
  if ($line =~ /present\($tree,$depth,$node\)/) {
    $current = "\"farey,$tree,$depth,$node\"";

    # Shape represents layer

    if ($line =~ /measureLevel\($tree,$depth\)/) {
      $shape = "box";
    } elsif ($line =~ /meterLevel\($tree,$depth\)/) {
      $shape = "diamond";
    } elsif ($line =~ /durationLevel\($tree,$depth\)/) {
      $shape = "circle";
    } else {
      die("Unable to identify level type for tree \"$tree\", level \"$depth\".");
    }

    # Check to see if it's a possible chord
    if ($line =~ /possibleChord\($node\)/) {
	$possibleChord{$node} = 1;
    }


    # Compute the meter strength
    if (($line =~ /meterLevel\($tree,$depth\)/)
	or ($line =~ /durationLevel\($tree,$depth\)/)) {

      # Find the max
      if ($line =~ /meterStrengthMax\($tree,(\d+)\)/) {
	$strengthMax = $1 + 1;
      } else {
	die("Unable to determine meter strength max for tree \"$tree\"");
      }


      # Find the meter strength
      if ($line =~ /nodeMeterStrength\($tree,$depth,$node,(\d+)\)/) {
	$strength = (1 - (($1 + 1) / $strengthMax));
      } else {
	# For notes that aren't the first child
	$strength = (1 - (1 / $strengthMax));
      }

    } else {
      $strength = 0;
    }

    print "$current [ label=\"$node\" shape=\"$shape\" color=\"0.000 0.000 $strength\"];\n";
  } else {
    die("present($tree,$depth,$node) expected but not found.");
  }

  # Note the duration
  $nodeDuration{"\"farey,$tree,$depth,$node\""} = $duration;

  # See if we need to recurse
  if ($line =~ /expand\($tree,$depth,$node,([0-9]+)\)/) {
    $expansion = $1;

    # Recurse and print link
    for ($i = 0; $i < $expansion; ++$i) {
      print "$current -- " . graphvizWalkFareyTree($line,$tree,$maxExpansion,$depth+1,(($maxExpansion * $node) + $i),($duration * $expansion)) . ";\n";
    }

  } else {
    # Sanity check
    if ($depth != fareyTreeDepth($line,$tree)) {
      die("present($tree,$depth,$node) and not at full depth but has no expansion?");
    }
  }

  return $current;
}

sub humanWalkFareyTree {
  my $line = shift;
  my $tree = shift;
  my $maxExpansion = shift;
  my $depth = shift;
  my $node = shift;
  my $duration = shift;
  my $current;
  my $expansion;
  my $i;


  # Note the duration
  $nodeDuration{"\"farey,$tree,$depth,$node\""} = $duration;

  # Check to see if it's a possible chord
  if ($line =~ /possibleChord\($node\)/) {
    $possibleChord{$node} = 1;
  }

  # See if we need to recurse
  if ($line =~ /expand\($tree,$depth,$node,([0-9]+)\)/) {
    $expansion = $1;

    if ($expansion > 1) {
      print "(";
    }

    # Recurse and print link
    for ($i = 0; $i < $expansion; ++$i) {
      if ($i > 0) {
	print " ";
      }

      humanWalkFareyTree($line,$tree,$maxExpansion,$depth+1,(($maxExpansion * $node) + $i),($duration * $expansion));

    }

    if ($expansion > 1) {
      print ")";
    }

  } else {
    # Sanity check
    if ($depth != fareyTreeDepth($line,$tree)) {
      die("present($tree,$depth,$node) and not at full depth but has no expansion?");
    }

    print "X";
  }

  return $current;
}


sub lilypondWalkFareyTree {
  my $line = shift;
  my $tree = shift;
  my $maxExpansion = shift;
  my $depth = shift;
  my $node = shift;
  my $duration = shift;
  my $endOfMeasure = shift;
  my $newDuration;
  my $current;
  my $expansion;
  my $i;
  my $descendantDepth;
  my $endOfMeasureInvert = 0;


  # Note the duration & if it's an end
  $nodeDuration{"\"farey,$tree,$depth,$node\""} = $duration;
  $lastNode{"\"farey,$tree,$depth,$node\""} = $endOfMeasure;

  # See if we need to recurse
  if ($line =~ /expand\($tree,$depth,$node,([0-9]+)\)/) {
    $expansion = $1;

    # Compute new duration and note if this is in the measure level
    $descendantDepth = $depth + 1;
    if ($line =~ /measureLevel\($tree,$descendantDepth\)/) {
      $newDuration = 1 * $duration;
      $endOfMeasureInvert = 1;
    } elsif ($line =~ /meterLevel\($tree,$descendantDepth\)/) {
      $newDuration = 2 * $duration;
    } elsif ($line =~ /durationLevel\($tree,$descendantDepth\)/) {
      $newDuration = $expansion * $duration;
    } else {
      die("Unable to identify level type for tree \"$tree\" and level \"$descendantDepth\"");
    }

    # Recurse
    for ($i = 0; $i < $expansion; ++$i) {
      lilypondWalkFareyTree($line,$tree,$maxExpansion,$depth+1,
                            (($maxExpansion * $node) + $i),$newDuration,
                             $endOfMeasure * ($endOfMeasureInvert ^ (($i == $expansion - 1) ? 1 : 0)));
    }


  } else {
    # Sanity check
    if ($depth != fareyTreeDepth($line,$tree)) {
      die("present($tree,$depth,$node) and not at full depth but has no expansion?");
    }
  }
}

sub exampleWalkFareyTree {
  my $line = shift;
  my $tree = shift;
  my $maxExpansion = shift;
  my $depth = shift;
  my $node = shift;
  my $duration = shift;
  my $current;
  my $expansion;
  my $i;


  # Note the duration
  $nodeDuration{"\"farey,$tree,$depth,$node\""} = $duration;

  # See if we need to recurse
  if ($line =~ /expand\($tree,$depth,$node,([0-9]+)\)/) {
    $expansion = $1;

    # If we're at meterLeafLevel or duration level
    if (($line =~ /meterLeafLevel\($tree,$depth\)/)
	or ($line =~ /durationLevel\($tree,$depth\)/)) {

      # Output the expansion
      print "expand($tree,$depth,$node,$expansion).\n";
    }


    # Recurse
    for ($i = 0; $i < $expansion; ++$i) {
      exampleWalkFareyTree($line,$tree,$maxExpansion,$depth+1,(($maxExpansion * $node) + $i),($duration * $expansion));
    }

  } else {
    # Sanity check
    if ($depth != fareyTreeDepth($line,$tree)) {
      die("present($tree,$depth,$node) and not at full depth but has no expansion?");
    }
  }
}

sub walkFareyTree {
  my $line = shift;
  my $tree = shift;
  my $maxExpansion = shift;
  my $depth = shift;
  my $node = shift;
  my $duration = shift;
  my $current;
  my $expansion;
  my $i;


  # Note the duration
  $nodeDuration{"\"farey,$tree,$depth,$node\""} = $duration;

  # See if we need to recurse
  if ($line =~ /expand\($tree,$depth,$node,([0-9]+)\)/) {
    $expansion = $1;

    # Recurse
    for ($i = 0; $i < $expansion; ++$i) {
      walkFareyTree($line,$tree,$maxExpansion,$depth+1,(($maxExpansion * $node) + $i),($duration * $expansion));
    }

  } else {
    # Sanity check
    if ($depth != fareyTreeDepth($line,$tree)) {
      die("present($tree,$depth,$node) and not at full depth but has no expansion?");
    }
  }
}


sub displayChord {
  my $line = shift;
  my $pc = shift;

  if ($line =~ /chord\($pc,\"([a-zA-Z0-9 ]+)\"\)/) {
    if ($1 eq "tonic") {
      print "T";
    } elsif ($1 eq "dominant") {
      print "D";
    } elsif ($1 eq "subdominant") {
      print "S";
    } else {
      die("Unknown chord at possible chord $pc : \"$1\"");
    }
  } else {
    print " ";
  }
	      
  if ($line =~ /chordPosition\($pc,\"([a-zA-Z0-9 ]+)\"\)/) {
    if ($1 eq "base") {
      print "0";
    } elsif ($1 eq "first inversion") {
      print "1";
    } elsif ($1 eq "second inversion") {
      print "2";
    } else {
      die("Unknown chord position at possible chord $pc : \"$1\"");
    }
  } else {
    print " ";
  }
	      
  # Align with notes
  print " ";
}

sub displayCadence {
  my $line = shift;
  my $pc = shift;
  
  if ($line =~ /cadence\($pc,\"([a-zA-Z0-9 ]+)\"\)/) {
    if ($1 eq "perfect") {
      print "pr ";
    } elsif ($1 eq "plagual") {
      print "pl ";
    } elsif ($1 eq "imperfect") {
      print "im ";
    } else {
      die("Unknown cadence at possible chord $pc : \"$1\"");
    }
   } else {
      print "   ";
   }
}


sub partToFareyTree {
  my $line = shift;
  my $part = shift;

  if ($line =~ /partToFareyTree\($part,([0-9]+)\)/) {
    return $1;
  } else {
    die("Can't find the Farey tree for part $part.");
  }
}

sub fareyTreeDepth {
  my $line = shift;
  my $depth = shift;

  # Find it's depth
  if ($line =~ /depth\($tree,([0-9]+)\)/) {
    return $1;
  } else {
    die("Can't find the depth of Farey tree $tree.");
  }
}

sub fareyTreeMaxExpansion {
  my $line = shift;
  my $tree = shift;

  if ($line =~ /maxExpansion\($tree,([0-9]+)\)/) {
    return $1;
  } else {
    die("Can find maxium expansion for Farey tree \"$tree\".");
  }
}


# Default options
$help = 0;
$output = "human";
$template = "";
$fundamental = "native";
$offset = 0;
$transpose = 0;
$defaultNoteDuration = 0.5;
$defaultMeasureDuration = 4;
$defaultAmplitude = -3;    # In decibels
$meterMultiplier = 1.5;

# GetOpt
Getopt::Long::GetOptions("help" => \$help, "output=s" => \$output,
                         "fundamental=s" => \$fundamental,
                         "template=s" => \$template,
                         "transpose=i" => \$transpose,
                         "note-duration=f" => \$defaultNoteDuration,
			 "measure-duration=f" => \$defaultMeasureDuration,
                         "amplitude=i" => \$defaultAmplitude);

# Help
if ($help) {
  print STDERR "Usage " . __FILE__ . " [options]\n";
  print STDERR "Options:\n";
  print STDERR "\t--help\t\tPrints this message.\n";
  print STDERR "\t--output=s\tOne of " . ( join ", ", @validOutputs ) . "\n";
  print STDERR "\t--template=s\tWhich csound template to use.\n";
  print STDERR "\t--fundamental=s\tSets the start note of the piece, i.e. C, D+\n";
  print STDERR "\t--transpose=i\tTranspose the piece down by the given number of octives.\n";
  print STDERR "\t--note-duration=f\tThe default duration of a note.\n";
  print STDERR "\t--measure-duration=f\tThe default duration of a measure.\n";
  print STDERR "\t--amplitude=i\tThe default amplitude in decibels.\n";
  print STDERR "\n";

  exit 0;
}

# Validate
$found = 0;
for $validOutput (@validOutputs) {
  if ($output =~ /$validOutput/i) {
    $output = $validOutput;
    $found = 1;
    last;
  }
}

if ($found == 0) {
  die("Unknown output type \"$output\".");
}



if ($fundamental =~ /^[A-G]$/i) {
  $fundamental = " " . uc $fundamental;
} elsif ($fundamental =~ /^[A-G]\+$/i) {
  $fundamental = uc $fundamental;
} elsif ($fundamental eq "native" ) {
  # Will auto select based on mode
} else {
  die "Unknown fundamental \"$fundamental\"\n";
}

if ($template eq "") {
  if ($output eq "csound") {
    $template = "basic";     # Default
  }
} else {
  if ($output ne "csound") {
    print STDERR "Template option only used for csound output";
  }
}

if ($defaultNoteDuration <= 0) {
  die("Default note duration ($defaultNoteDuration) must be strictly positive.");
}

if ($defaultMeasureDuration <= 0) {
  die("Default measure duration ($defaultMeasureDuration) must be strictly positive.");
}

if (($defaultAmplitude > -1) or ($defaultAmplitude < -100)) {
  die("Amplitude must be in decibels, range [-100,-1].");
}


# Calculate the offset
for ($i = 0; $i < 12; ++$i) {
  if ($noteNames[$i] eq $fundamental) {
    $offset = $i;
    last;
  }
}



## Headers
# If in CSound mode, print out the necessary header
#if (($output eq "csound") or ($output eq "csound-advanced")) {
if ($output eq "csound") {
  open(FH,"csound-templates/$template.csd") or die("Can't open template \"$template\"");

  while (<FH>) {
    if ($_ =~ /;; GENERATED TUNES GO HERE/) {
      # Have finished the header
      last;
    } else {
      print $_;
    }
  }

} elsif ($output eq "lilypond") {

  if ($defaultNoteDuration != 0.5) {
    print STDERR "Note duration not supported in Lilypond output";
  }
  
  # Due to the way layer names are created...
  print "\% lilypound output is currently limited to $layerLimit layers.\n";
  print "\\version \"2.10.33\"\n";
  print "\\paper { indent = 0\\cm }\n"; # Turn off indent 

}


# Work through the input
$answerSets = 0;
while ((($type,$line) = parseAnswerSet(\*STDIN)) && ($type ne "End")) {
  
  if ($type eq "Answer Set") {
    ++$answerSets;

    if ($fundamental eq "native") {
      if ($line =~ /mode\(([a-z]+)\)/) {
	$offset = 0 if (($1 eq "major") or ($1 eq "minor"));
	$offset = 2 if ($1 eq "dorian");
	$offset = 4 if ($1 eq "phrygian");
	$offset = 5 if ($1 eq "lydian");
	$offset = 7 if ($1 eq "mixolydian");

      } else {
	die "Unable to identify mode and no fundamental note set.\n";
      }
    }
    if ($output eq "lilypond") {
      # Mode is needed for lilypond regardless of fundamental
      if ($line =~ /mode\(([a-z]+)\)/) {
	$mode = $1;
      } else {
	die "Unable to identify mode.\n";
      }
    }

    if ($line =~ /style\(([a-z]+)\)/) {
	$style = "solo" if ($1 eq "solo");
	$style = "duet" if ($1 eq "duet");
	$style = "trio" if ($1 eq "trio");
	$style = "quartet" if ($1 eq "quartet");
    }

    # Traditional csound format
    if ($output eq "csound") {
      print "; Starting answer set $answerSets\n";

      # Output format
      # iX = instrument X
      # 0 = when to play (in meters, seconds by default)
      #     + adds on the duration of the preceeding note
      # 0.5 = duration (in same units)
      #       . value of the preceeding note for the given instrument
      # 8.00 = pitch (octave.note, note is 0-11, 8.00 is middle C)
      # -3 = amplitude, in decibels, 0 is everything, -100 is nothing

      # Compute piece length
      if ((isUsingRhythm($line)) and ($line =~ /measureLimit\((\d+)\)/)) {
	$duration = $1 * $defaultMeasureDuration;
      } else {
	$t = 1;
	while ($line =~ /time\($t\)/) { ++$t; }
	--$t;
	$duration = $t * $defaultNoteDuration;
      }

      # For each part
      $part = 1;
      while ($line =~ /part\($part\)/) {
	
	# Compute note durations
	if (isUsingRhythm($line)) {
	  $tree = partToFareyTree($line,$part);
	  $depth = fareyTreeDepth($line,$tree);
	  $maxExpansion = fareyTreeMaxExpansion($line,$tree);
	  walkFareyTree($line,$tree,$maxExpansion,1,0,1);
	}
	
	# For each time step, print a note / rest
	$t = 1;
	while ($line =~ /partTime\($part,$t\)/) {
	  if ($line =~ /choosenNote\($part,$t,([0-9]+)\)/) {
	    print "i$part 0 " if ($t == 1);
	    print "i$part + " if ($t != 1);

	    if (isUsingRhythm($line)) {
	      if ($line =~ /timeToNode\($part,$t,([0-9]+)\)/) {
		$node = $1;
		print ($duration / $nodeDuration{"\"farey,$tree,$depth,$node\""});

		if ($line =~ /nodeMeterStrength\($tree,$depth,$node,(\d+)\)/) {
		  $amplitude = csoundAmplitude($line,$defaultAmplitude,$1,$meterMultiplier);
		} else {
		  $amplitude = csoundAmplitude($line,$defaultAmplitude,0,$meterMultiplier);
		}

	      } else {
		die("Can't find node \"$node\" for part \"$part\" at time \"$t\"");
	      }

	    } else {
	      print "$defaultNoteDuration";
	      $amplitude = csoundAmplitude($line,$defaultAmplitude,0,$meterMultiplier);
	    }

	    csoundFormat($1,$offset,$transpose,$amplitude);

	  } elsif ($line =~ /rest\($part,$t\)/) {
	    # As time keeping is acumulative, need a note with zero amplitude
	    print "i$part 0 " if ($t == 1);
	    print "i$part + " if ($t != 1);
	    
	    if (isUsingRhythm($line)) {
	      if ($line =~ /timeToNode\($part,$t,([0-9]+)\)/) {
		$node = "\"farey,$tree,$depth,$1\"";
		print ($duration / $nodeDuration{$node});
	      } else {
		die("Can't find node for part \"$part\" at time \"$t\"");
	      }
	    } else {
	      print "$defaultNoteDuration";
	    }

	    print "8.00 0\n";

	  } else {
	    die("Can't work out what part $part does at time $t.");
	  }
	  ++$t;
	}

	++$part;
      }

      print "f0 ";
      print $t/2;
      print "\ns\n";
      print "; Finishing answer set $answerSets\n\n";

    } elsif ($output eq "lilypond") {

      print "% Starting answer set $answerSets\n";

      $modeName = $noteNamesLilypond[$offset];
      
      $part = 1; 
      while ($line =~ /part\($part\)/ && $voicecount < $layerLimit) {
	printf ("layer%c%c = {\n", 65 + int($voicecount / 26.0), 65 + ($voicecount % 26));
	$voicecount++;
	print "\t\\clef treble \n";
	print "<< { \\key " . $modeName . " \\" . $mode . " \n";

	if (isUsingRhythm($line)) {
	  $tree = partToFareyTree($line,$part);
	  $depth = fareyTreeDepth($line,$tree);
	  $maxExpansion = fareyTreeMaxExpansion($line,$tree);
	  lilypondWalkFareyTree($line,$tree,$maxExpansion,1,0,1,1);
          if ($line =~ /treeTimeSignature\($tree,\"([0-9\/a-zA-Z\-]*)\"\)/) {
	      $treeTimeSignature = $1;

              # Check for the generic N-layer variable time signatures
	      if ($treeTimeSignature =~ /\//) {
		  print "\\time $treeTimeSignature\n";
		  $endOfBar = " | \n";
		  # Need to auto identify the N-layer signatures
	      } else {
		  print "\\set Score.timing = \#\#f\n";
		  $endOfBar = " \\bar \"|\"\n";
	      }
	  } else {
	      print STDERR "Unable to find time signature for tree \"$tree\".\n";
	  }
	} else {
	    print "\\set Score.timing = \#\#f\n";
	    $endOfBar = " \\bar \"|\"\n";
	}
	
	$t = 1;
	while ($line =~ /partTime\($part,$t\)/) {
	  if ($line =~ /choosenNote\($part,$t,([0-9]+)\)/) {

	    if (isUsingRhythm($line)) {
	      if ($line =~ /timeToNode\($part,$t,([0-9]+)\)/) {
		$node = "\"farey,$tree,$depth,$1\"";
		$duration = $nodeDuration{$node};

		# Close triple if needed
		if ($tripletOpen == 3) {
		  print " } ";
		  $tripletOpen = 0;
		}

                # Open triplet if needed
		if ($duration % 3 == 0) {
		  if ($tripletOpen == 0) {
		    print " \\times 2/3 {";
		    $tripletOpen = 1;
		  } else {
		    ++$tripletOpen;
		  }
		  $duration = ($duration / 3) * 2; 
		}
	      } else {
		die("Can't find node for part \"$part\" at time \"$t\"");
	      }
	    } else {
	      $duration = 1;
	    }


	    print $noteNamesLilypond[ (($1 + 35 + $offset) % 12) ];

	    if ($1 + 35 + $offset + (12 * $transpose) > 83) {
	      print "'''$duration";
	    } elsif ($1 + 35 + $offset + (12 * $transpose) > 71) {
	      print "''$duration";
	    } elsif ($1 + 35 + $offset + (12 * $transpose) > 59) {
	      print "'$duration";
	    } elsif ($1 + 35 + $offset + (12 * $transpose) > 47) {
	      print "$duration";
	    } elsif ($1 + 35 + $offset + (12 * $transpose) > 35) {
	      print ",$duration";
	    } elsif ($1 + 35 + $offset + (12 * $transpose) > 23) {
	      print ",,$duration";
	    } else {
	      die("Don't know how to format part $part, time $t with value " . ($1 + 35 + $offset + (12 * $transpose)) . "." );
	    }

	  } elsif ($line =~ /rest\($part,$t\)/) {
	    print " r";
	  } else {
	    die("Can't work out what part $part does at time $t.");
	  }
	  ++$t;

	  # If using rhythm print bar lines for measures
	  if (isUsingRhythm($line)) {
	   if ($lastNode{$node} == 1) {
	       print $endOfBar;
           }
	  }
	}
	
	print "\n \\bar \"||\" \\break \n}\n";
	print ">>\n}\n";
	
	++$part;
	$numvoices = $part - 1
      }
      print "% Finishing answer set $answerSets\n\n";
      

    } elsif ($output eq "example") { 

      if (isUsingRhythm($line)) {
	print "rhythm(1).\n";

	# First the measure controls
	if ($line =~ /measureLimit\(([0-9]+)\)/) {
	  print "measureLimit($1).\n";
	} else {
	  die("Rhythm enabled but no measureLimit found.\n");
	}

	if ($line =~ /measureDepth\(([0-9]+)\)/) {
	  print "measureDepth($1).\n";
	} else {
	  die("Rhythm enabled but no measureDepth found.\n");
	}

	$part = 1;
	while ($line =~ /part\($part\)/) {

	  $tree = partToFareyTree($line,$part);

	  # Now time signatures
	  if ($line =~ /treeTimeSignature\($tree,(\"[0-9\/]+\")\)/) {
	    print("treeTimeSignature($tree,$1).\n");
	    print("meterDepthConfig($tree,$1).\n");
	  } else {
	    die("Unable to find time signature for tree $tree.\n");
	  }
	
          # Divisions
	  $depth = fareyTreeDepth($line,$tree);
	  $maxExpansion = fareyTreeMaxExpansion($line,$tree);
	  exampleWalkFareyTree($line,$tree,$maxExpansion,1,0,1);

	  ++$part;
	}
	
      }


      if ($line =~ /mode\(([a-z]*)\)/) {
	print "mode($1).\n";
      } else {
	die("Unable to identify mode.\n");
      }
      
      $part = 1;
      while ($line =~ /part\($part\)/) {
	print "part($part).\n";
	$t = 1;
	while ($line =~ /choosenNote\($part,$t,([0-9]+)\)/) {
	  print "choosenNote($part,$t,$1).\n";
	  ++$t;
	}
	--$t; # Correct;
	print "partTimeMax($part,$t).\n";

	++$part;
      }
      
      if ($line =~ /style\(([a-z]*)\)/) {
	print "style($1).\n";
      } else {
	die("Unable to identify style.\n");
      }
      
      
    } elsif ($output eq "human") {
      
      $part = 1;
      $pieceTimeLimit = 0;
      
      while ($line =~ /part\($part\)/) {
	
	# Print the midi number
	$t = 1;
	while ($line =~ /partTime\($part,$t\)/) {
	  if ($line =~ /choosenNote\($part,$t,([0-9]+)\)/) {
	    print ($1 + 35 + $offset + (12 * $transpose));
	  } elsif ($line =~ /rest\($part,$t\)/) {
	    print "--";
	  } else {
	    print "??";
	  }
	  print " ";
	  ++$t;
	}
	print"\n";

	
	# Print the note name
	$t = 1;
	while ($line =~ /partTime\($part,$t\)/) {
	  if ($line =~ /choosenNote\($part,$t,([0-9]+)\)/) {
	    print $noteNames[ (($1 + 35 + $offset) % 12) ];
	    if ($1 + 35 + $offset + (12 * $transpose) > 71) {
	      # Need primes to display correctly
	      if ($1 + 35 + $offset + (12 * $transpose) > 83) {
		print"\"";
	      } else {
		print "'";
	      }
	    } else {
	      print " ";
	    }
	  } elsif ($line =~ /rest\($part,$t\)/) {
	    print " - ";
	  } else {
	    print "?? ";
	  }
	  
	  ++$t;
	}

	print"\n";

	# Print the transitions
	print "  ";
	$timeLimit = $t - 1;
	for ($t = 1; $t < $timeLimit; ++$t) {
	  if (($line =~ /stepBy\($part,$t,([\-0-9]+)\)/) ||
               ($line =~ /leapBy\($part,$t,([\-0-9]+)\)/)   ) {

            if ($1 < 0) {
              print "$1";
            } else {
              print "+$1";
            }
          } elsif ($line =~ /repeated\($part,$t\)/) {
	    print "\"\"";
	  } elsif ($line =~ /incorrectProgression\($part,$t\)/) {
	    print "XX";
	  } elsif ($line =~ /toRest\($part,$t\)/) {
	    print "-\\";
	  } elsif ($line =~ /fromRest\($part,$t\)/) {
	    print "/-";
	  } else {
            print "??";
	  }

	  print " ";

	}
	print "\n";

	# Optionally, print the rhythm
	if (isUsingRhythm($line)) {
	  $tree = partToFareyTree($line,$part);
	  $maxExpansion = fareyTreeMaxExpansion($line,$tree);
	  humanWalkFareyTree($line,$tree,$maxExpansion,1,0,1);
	}

	print "\n\n";

	$pieceTimeLimit = $timeLimit if ($pieceTimeLimit < $timeLimit);
	++$part;
      }


      if (isUsingChords($line)) {
	if (isUsingRhythm($line)) {
	  foreach $key (sort keys %possibleChord) {
	      displayChord($line,$key);
	  }
	  print "\n";

	  foreach $key (sort keys %possibleChord) {
	      displayCadence($line,$key);
	  }

	} else {
	  # Display chords
	  for ($t = 1; $t <= $pieceTimeLimit; ++$t) {
	    displayChord($line,$t);
	  }
	  print "\n";

	  # Display cadances
	  for ($t = 1; $t <= $pieceTimeLimit; ++$t) {
	    displayCadence($line,$t);
	  }
	}

	print "\n\n";
      }


      print "----\n\n";

    } elsif ($output eq "graphviz") {

      isUsingRhythm($line) or die("Graphviz output only handles rhythm, input does not seem to use rhythm.");

      # Wipe global variables
      %nodeDuration = ();
      %possibleChord = ();

       print "graph G {\n";

      # Find the length of the piece
      $part = 1;
      $pieceTimeLimit = 0;
      while ($line =~ /part\($part\)/) {
	if ($line =~ /partTimeMax\($part,(\d+)\)/) {
	  $pieceTimeLimit = $1 if ($1 > $pieceTimeLimit);
	} else {
	  die("Unable to find partTimeMax for part \"$part\"");
	}
	$part++;
      }
      $duration = $defaultNoteDuration * $pieceTimeLimit;

      # Display the trees
      $tree = 1;
      while ($line =~ /fareyTree\($tree\)/) {
	print "subgraph cluster_fareyTree_$tree {\n";
	print "label=\"fareyTree($tree)\";\n";
	print "rankdir=\"TB\"\n";

	# Find the maximum expansion
	$maxExpansion = fareyTreeMaxExpansion($line,$tree);

	# Recursively parse as we also want to compute duration
	graphvizWalkFareyTree($line,$tree,$maxExpansion,1,0,1);

	print "}\n";

	++$tree;
      }



      # Display the mapping to notes and parts
      $part = 1;
      $displayNotes = 1;
      $displayLinks = 1;
      while ($displayNotes && ($line =~ /part\($part\)/)) {

	print "subgraph cluster_part_$part {\n";
	print "label=\"part($part)\";\n";

	$tree = partToFareyTree($line,$part);
	$depth = fareyTreeDepth($line,$depth);

	$t = 1;
	while ($line =~ /partTime\($part,$t\)/) {

	  # Try to find the corresponding node
	  if ($line =~ /timeToNode\($part,$t,([0-9]+)\)/) {
	    $node = "\"farey,$tree,$depth,$1\"";

	    print "\"note,$part,$t\" [label=\"" . ($duration / $nodeDuration{$node}) . "\", shape=box];\n";
	    if ($displayLinks) {
	      print "\"note,$part,$t\" -- $node;\n";
	    }
	
	  } else {
	    print "\"note,$part,$t\" [label=\"\", shape=box];\n";
	  }

	  # Link to help layout
	  if ($t > 1) {
	    print "\"note,$part,$t\" -- \"note,$part," . ($t-1) . "\";\n";
	  }

	  ++$t;
	}

	print "}\n";
	++$part;
      }

      # Display overlaps between nodes
      my $literal;
      my $f1;
      my $nd1;
      my $f2;
      my $nd2;
      my $dll1;
      my $dll2;

      for $literal (split / /, $line) {
	if ($literal =~ /nodeOverlap\((\d+),(\d+),(\d+),(\d+)\)/) {
	  $f1 = $1;
	  $nd1 = $2;
	  $f2 = $3;
	  $nd2 = $4;

	  if ($line =~ /durationLeafLevel\($f1,(\d+)\)/) {
            $dll1 = $1;
	    if ($line =~ /durationLeafLevel\($f1,(\d+)\)/) {
	      $dll2 = $1;

	      print "\"farey,$f1,$dll1,$nd1\" -- \"farey,$f2,$dll2,$nd2\" [ style=\"dotted\" ];\n";

            }
          }
	}
      }

      # Display overlap between notes
      my $p1;
      my $t1;
      my $p2;
      my $t2;
      for $literal (split / /, $line) {
        if ($literal =~ /noteOverlap\((\d+),(\d+),(\d+),(\d+)\)/) {
	  print "\"note,$1,$2\" -- \"note,$3,$4\" [ style=\"dotted\" ];\n";
	}
      }

      print "}\n\n";
    } 
  }
}



## Footers
#if (($output eq "csound") or ($output eq "csound-advanced")) {
if ($output eq "csound") {
  print <FH>;
  close(FH);
} elsif ($output eq "lilypond") {
  
  print "\n";
  print "\\score {\n";
  print "\\new StaffGroup <<\n";
  for ($part=0; $part < $numvoices; $part++)
    {
      print "\\transpose " . $noteNamesLilypond[$offset] . " c {"; 
      print "\\new Staff { \\override Staff.TimeSignature #'break-visibility = #end-of-line-invisible"; #  "\\set Score.timing = \#\#f";
      
      for ($i=1+$part; $i < $voicecount; $i+=$numvoices)
	{
	  printf (" \\layer%c%c", 65 + int($i / 26.0), 65 + ($i % 26));
	}
      print " } }\n";
    }
  
  print ">>\n\\layout {}\n}\n";
}




