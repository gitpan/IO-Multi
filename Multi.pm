package IO::Multi;

use strict;

=head1 NAME

IO::Multi - IO interface for treating multiple seekable IO-objects (i.e. Files)
as one single object.


=head1 SYNOPSIS

There's only an OO interface in this version, so you have to use

use IO::Multi;
use IO::File;

# open 2 files and construct a multi-object with them
my $fh1=IO::File->new('/tmp/file1');
my $handle=IO::File->new('/tmp/file2');
my $multi=IO::Multi->new($fh1,$handle2);

# add a 3rd object to the multi-object
my $next=IO::File->new('/tmp/file3');
$multi->add($next);

# seek, read and tell work as always

# assume the file's data changed (of one or more files), we have to re-read
# their information
$multi->refresh();

# write, print and printf are NOT functional!

=head1 DESCRIPTION

This module implements the possibility to treat multiple seekable IO-objects as
one single object for reading and writing. Useful if you have splitted files
(from disks for example) and do not want/have the space to join them before
opening them. This code is (should be?) optimized for high performance and low
memory consumption. Please read the AUTHOR part below.


=head1 VERSION

Revision: 0.02

=cut

use vars '$VERSION';

$VERSION = substr q$Revision: 2.104 $, 10;


################################################################################
# methods
#

=head1 CONSTRUCTOR

=over 4

=item new([IO-OBJECTS])

Creates a new multi-object from optionally given IO-OBJECTS (filehandles).

Returns an instance of this class if all IO-OBJECTS (if any) support read(),
seek() and tell() (will be used for determining their sizes) and have a
size of one byte at least.

You may use add() to add filehandles later.

=cut

sub new {
	my $proto=shift;
	my $class=ref($proto) || $proto;
	my $self=bless {
		handles=>[],
		handles_size=>[],
		currenthandle=>0,
		size=>0,
		pos=>0,
		lastpos=>0,
		handlepos=>0,
		},$class;
	return undef unless $self->_add_handles(@_);
	$self;
}


=back

=head1 METHODS

=over 4

=item add(IO-OBJECT[S])

Adds one ore more IO-OBJECTS (filehandles) to the previously created instance of
this class.

Returns TRUE on success, FALSE on failure. Note that all IO-OBJECTS have to
support read(), seek() and tell() and must be at least one byte of size.

If one objects from a given list fails the internal verification no object will
be added.

=cut

sub add {
	my $self=shift;
	$self->_add_handles(@_);
}


=item refresh()

"refreshes" internal file-information. Useful if any of the IO-OBJECTS the
IO::Multi instance is currently made of has changed size.

Returns TRUE on success, FALSE on failure. Do not forget to test the return-
value! If this method fails, this instance of IO::Multi will be empty and
therefore unaccessable.

=cut

# test return value!
sub refresh() {
	my $self=shift;
	$self->_reset_pos();
	my @handles=@{$self->{handles}};
	$self->_reset_handles();
	$self->_add_handles(@handles)
}


=item read(SCALAR,LENGTH[,OFFSET])

Reads LENGTH bytes to SCALAR (to offset OFFSET). Starts at position 0 inside the
SCALAR if OFFSET is omitted. SCALAR will be cleared (from OFFSET).

Returns the number of bytes actually read, 0 on end of file, undef on error
(if read() fails on the internally selected IO-OBJECT).

=cut

sub read($$;$) {
	my $self=shift;
	my $buf=\shift;
	my $length=shift;
	my $offset=shift || 0;

	return 0 unless $length && $self->_seek_set_pos(); # read nothing? invalid pos?

	$$buf='' unless defined $$buf;
	substr($$buf,$offset)='' if $offset && length $$buf >= $offset;

	my ($readlength,$handle)=($length,$self->{currenthandle});
	while ($readlength) {
		return undef unless defined (my $read=$self->{handles}->[$handle]->read($$buf,$readlength,$offset));
		$readlength-=$read;
		$offset+=$read;
		if ($readlength) {
			unless ($self->{handles}->[++$handle]) { $handle--; last }
			$self->{handles}->[$handle]->seek(0,0); # SEEK_SET
		}
	}
	$self->{pos}+=$length-$readlength;
	$self->{lastpos}=$self->{pos};
	$self->{handlepos}=$self->{handles}->[$handle]->tell();
	$self->{currenthandle}=$handle;

	$length-$readlength;
}


=item seek(POS,WHENCE)

Sets the internal pointer to position POS. Refer to perlfunc::seek for possible
values for WHENCE.

Returns the number of bytes actually read, 0 on end of file, undef on error
(if read() fails on the internally selected IO-OBJECT).

=cut

sub seek($$) {
	my $self=shift;
	my ($pos,$whence)=@_;

	if ($whence==0) { # SEEK_SET
		$self->{pos}=$pos;
	} elsif ($whence==1) { # SEEK_CUR
		$self->{pos}+=$pos;
	} elsif ($whence==2) { # SEEK_END
		$self->{pos}=$self->{size}+$pos;
	} else { return undef }
	$self->{pos}=$self->{pos}<0?0:$self->{pos}>$self->{size}?$self->{size}:$self->{pos};
}


=item eof()

Determines whether the pointer is at the end of the file or not and returns
TRUE or FALSE, depending on if it is at the end of the file or not.

=cut

sub eof() {
	my $self=shift;
	$self->{pos}>=$self->{size}?1:0;
}


=item tell()

Returns the current position of the pointer.

=cut

sub tell {
	shift->{pos};
}


=item write()

UNIMPLEMENTED!

Will cause immediate death.

=cut

sub write {
	die"IO::Multi-objects may be used only for reading! write is not supported (tried by ".caller().")!\n";
}


=item print()

UNIMPLEMENTED!

Will cause immediate death.

=cut

sub print {
	die"IO::Multi-objects may be used only for reading! print is not supported (tried by ".caller().")!\n";
}


=item printf()

UNIMPLEMENTED!

Will cause immediate death.

=cut

sub printf {
	die"IO::Multi-objects may be used only for reading! printf is not supported (tried by ".caller().")!\n";
}


sub flush {}

sub autoflush {}

sub binmode {}

sub clearerr {1}

=item close()

Frees all internal structures and filehandles.

There is no explicit need to call this method, it will automatically be called
when the instance is destroyed.

=cut

sub close() {
	my $self=shift;
	$self->_reset_pos();
	$self->_reset_handles();
	1;
}


################################################################################
# private methods not to be called from outside this module
#

sub _add_handles { # returns TRUE except in case of failure (even if theres no parameter)
	my $self=shift;
	return 1 unless @_;
	my ($size,@handles,@sizes)=(0);
	foreach (@_) {
		return undef unless _verify_handle($_);
		push @handles,$_;
		my $bytes=$_->tell();
		push @sizes,$bytes;
		$size+=$bytes;
	}
	push @{$self->{handles}},@handles;
	push @{$self->{handles_size}},@sizes;
	$self->{size}+=$size;
	1;
}


# this is not a method, just an ordinary sub!
sub _verify_handle($) {
	my $fh=shift;
	return undef unless $fh->seek(0,2); # SEEK_END
	return undef unless $fh->tell(); # 0 bytes
	1;
}


sub _reset_handles() {
	my $self=shift;
	$self->{handles}=[];
	$self->{handles_size}=[];
}


sub _reset_pos() {
	my $self=shift;
	$self->{currenthandle}=0;
	$self->{size}=$self->{pos}=$self->{lastpos}=$self->{handlepos}=0;
}


sub _seek_set_pos() {
	my $self=shift;
	return undef if $self->{pos}>=$self->{size};
	my ($handle,$chunksizes,$pos)=(0,$self->{handles_size}->[0],$self->{pos});
	if ($pos==$self->{lastpos}) { # are we just reading on?
		$handle=$self->{currenthandle};
		$pos=$self->{handlepos};
	} else { # find the handle we have to read with
		until ($pos<$self->{handles_size}->[$handle]) {
			$pos-=$self->{handles_size}->[$handle++];
			return undef unless $self->{handles}->[$handle]; # no ref? serious error!
		}
		$self->{currenthandle}=$handle;
		$self->{handlepos}=$pos;
		$self->{lastpos}=$self->{pos};
	}
	$self->{handles}->[$handle]->seek($pos,0); # SEEK_SET
}


sub DESTROY() {
	shift->close();
}

=back

=head1 AUTHOR

Written and maintained by Niklas Bichinger (niklas@groelaz.org).

This code is (or at least should be) optimized for high performance and low
ressources consumption. Therefore comments and suggestions are highly
appreciated!

Very much of this code was developed with the help of IO::stringy sources from
Eryq (eryq@zeegee.com) and Doru Petrescu (pdoru@kappa.ro).

=cut

1;
