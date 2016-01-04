=head1 LICENSE

Copyright [1999-2016] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


=head1 CONTACT

 Please email comments or questions to the public Ensembl
 developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

 Questions may also be sent to the Ensembl help desk at
 <http://www.ensembl.org/Help/Contact>.

=cut

=head1 NAME

Bio::EnsEMBL::Variation::ProteinHaplotype

=head1 SYNOPSIS

  use Bio::EnsEMBL::Variation::ProteinHaplotype;

=head1 DESCRIPTION

A class for representing a transcript's CDS sequence modified by sample
genotypes.

=cut

package Bio::EnsEMBL::Variation::ProteinHaplotype;

use strict;
use warnings;

use Bio::EnsEMBL::Variation::Utils::Sequence qw(align_seqs);
use Bio::EnsEMBL::Utils::Exception qw(throw);

use Bio::EnsEMBL::Variation::TranscriptHaplotype;

use base qw(Bio::EnsEMBL::Variation::TranscriptHaplotype);

=head2 new

  Arg [-CONTAINER]:  Bio::EnsEMBL::Variation::TranscriptHaplotypeContainer
  Arg [-SEQ]:        string
  Arg [-HEX]:        string
  Arg [-INDEL]:      bool

  Example    : my $ch = Bio::EnsEMBL::Variation::ProteinHaplotype->new(
                  -CONTAINER => $container,
                  -SEQ       => $seq,
                  -HEX       => $hex,
                  -INDEL     => $indel
               );

  Description: Constructor.  Instantiates a new ProteinHaplotype object.
  Returntype : Bio::EnsEMBL::Variation::DBSQL::ProteinHaplotype
  Exceptions : none
  Caller     : internal
  Status     : Stable

=cut

sub new {
  my $caller = shift;
  my $class = ref($caller) || $caller;
  
  my %args = @_;
  
  my $self = $class->SUPER::new(%args);
  bless($self, $class);

  $self->type('protein');
  
  return $self;
}


=head2 get_all_CDSHaplotypes

  Example    : my @chs = @{$ph->get_all_CDSHaplotypes()}
  Description: Get all CDSHaplotypes that translate to this ProteinHaplotype
  Returntype : arrayref of Bio::EnsEMBL::Variation::CDSHaplotype
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub get_all_CDSHaplotypes {
  return $_[0]->get_other_Haplotypes;
}


=head2 reference_seq

  Example    : my $ref_seq = $ph->reference_seq
  Description: Get the reference protein sequence
  Returntype : string
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub reference_seq {
  return $_[0]->transcript->{protein};
}


=head2 get_all_diffs

  Example    : my @diffs = @{$ph->get_all_diffs}
  Description: Get a list of differences to the reference. Each difference is a
               hashref containing a string 'diff' representing a change
               e.g. 19P>L represents a change of Proline to Leucine at position 19.

               The hashref may also contain keys representing predictions and scores
               from SIFT and PolyPhen.
  Returntype : arrayref of hashrefs
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub get_all_diffs {
  my $self = shift;
  
  if(!defined($self->{diffs})) {    
    my $matrices = $self->container->_get_prediction_matrices;
    
    my @diffs;

    my $seen_indel = 0;
    my $ref_length = length($self->reference_seq());
    
    foreach my $raw_diff(@{$self->_get_raw_diffs}) {
      
      my $diff = { diff => $raw_diff };
      
      # extract change from raw diff
      if($raw_diff =~ /^(\d+)[A-Z]\>([A-Z])$/ && !$seen_indel) {
        my $pos = $1;
        my $aa  = $2;

        # get sift/polyphen predictions from cached matrices
        # but only if within range
        if($pos <= $ref_length) {
          foreach my $tool(qw(sift polyphen)) {
            if(my $matrix = $matrices->{$tool}) {
              my ($pred, $score) = $matrix->get_prediction($pos, $aa);
              
              $diff->{$tool.'_score'}       = $score if defined($score);
              $diff->{$tool.'_prediction'}  = $pred if defined($pred);
            }
          }
        }
      }

      elsif($raw_diff =~ /ins|del/) {
        $seen_indel = 1;
      }
      
      push @diffs, $diff;
    }
    
    $self->{diffs} = \@diffs;
  }
  
  return $self->{diffs};
}


=head2 get_all_flags

  Example    : my @flags = @{$ph->get_all_flags}
  Description: Get a list of flags for this haplotype. Current possible
               flags are: "deleterious_sift_or_polyphen", "stop_change",
               "indel"
  Returntype : arrayref of strings
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub get_all_flags {
  my $self = shift;

  if(!exists($self->{flags})) {
    my @flags;
    for my $flag(qw(deleterious_sift_or_polyphen stop_change indel)) {
      my $method = 'has_'.$flag;
      push @flags, $flag if $self->$method;
    }
    $self->{flags} = \@flags;
  }

  return $self->{flags};
}


=head2 has_deleterious_sift_or_polyphen

  Example    : my $has_del = $ph->has_deleterious_sift_or_polyphen
  Description: Indicates if any of the protein differences are qualified
               as deleterious (SIFT) or probably damaging (PolyPhen)
  Returntype : boolean
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub has_deleterious_sift_or_polyphen {
  my $self = shift;

  my $has = 0;

  foreach my $diff(@{$self->get_all_diffs}) {
    $has = 1 if
      ($diff->{sift_prediction} && $diff->{sift_prediction} eq 'deleterious') ||
      ($diff->{polyphen_prediction} && $diff->{polyphen_prediction} eq 'probably damaging');
    last if $has;
  }

  return $has;
}


=head2 has_stop_change

  Example    : my $has_sc = $ph->has_stop_change
  Description: Indicates if this protein has any changes to the reference
               stop codon. This may be either a stop gain (truncating) or
               a stop lost (extending)
  Returntype : boolean
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub has_stop_change {
  my $self = shift;

  my $has = 0;

  foreach my $diff(@{$self->get_all_diffs}) {
    $has = 1 if $diff->{diff} =~ /\*/;
    last if $has;
  }

  return $has;
}


=head2 mean_sift_score

  Example    : my $score = @{$ph->mean_sift_score()}
  Description: Get the mean SIFT score across all diffs in this ProteinHaplotype
  Returntype : float
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub mean_sift_score {
  return $_[0]->_mean_score('sift');
}


=head2 mean_polyphen_score

  Example    : my $score = @{$ph->mean_polyphen_score()}
  Description: Get the mean PolyPhen score across all diffs in this ProteinHaplotype
  Returntype : float
  Exceptions : none
  Caller     : general
  Status     : Stable

=cut

sub mean_polyphen_score {
  return $_[0]->_mean_score('polyphen');
}

## used to calculate means for mean_sift_score and mean_polyphen_score
sub _mean_score {
  my $self = shift;
  my $tool = shift;
  
  my @scores = grep {defined($_)} map {$_->{$tool.'_score'}} @{$self->get_all_diffs};
  return undef unless @scores;
  
  my $sum = 0;
  $sum += $_ for @scores;
  
  return $sum / scalar @scores;
}

sub _reference_name {
  return $_[0]->transcript->translation->stable_id;
}

sub TO_JSON {
  my $self = shift;

  $self->get_all_flags;
  
  # make a hash copy of self
  my %copy = %{$self};
  
  # delete keys starting with _
  delete $copy{$_} for grep {$_ =~ /^\_/} keys %copy;
  
  return \%copy;
}

1;
