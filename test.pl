# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..11\n"; }
END {print "not ok 1\n" unless $loaded;}
use IO::Multi;
use IO::File;
$loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Insert your test code below (better if it prints "ok 13"
# (correspondingly "not ok 13") depending on the success of chunk 13
# of the test code):

print"Creating files '/tmp/IO-Multi-Test_[1..4]'...\n";
for (1..4) {
	print "not ok 2\n", die"Test impossible, file '/tmp/IO-Multi-Test_$_' exists.\n" if -e "/tmp/IO-Multi-Test_$_";
}
my $string='';
for (1..4) {
	open TMP,">/tmp/IO-Multi-Test_$_" || print "not ok 2\n", die "Test impossible.\n";
	my $chars='';
	$chars.=substr('abcdefghijklmnopqrstuvwxyz1234567890',rand(35),1) for (1..$_);
	$string.=$chars;
	print TMP $chars;
	close TMP;
}
print"Files created with content (of all 4 files) '$string'.\n";
print"ok 2\n";

print"Opening files with IO::File...\n";
my @files;
for (1..4) {
	push @files,IO::File->new("/tmp/IO-Multi-Test_$_",'r') || print "not ok 3\n", goto clear;
}
print "ok 3\n";

print "Constructing instance of IO::Multi from the 4 files...\n";
my $fh=IO::Multi->new(@files) || print "not ok 4\n", goto clean;
print "ok 4\n";

print "Size: $fh->{size}\n";

print "Seeking to end of file...\n";
$fh->seek(0,2);
print "Position from tell(): ".$fh->tell()."... ";
$fh->tell() == length($string)?print "ok\n":print "\nnot ok 5\n",goto clear;
print "eof() has to return true... ";
$fh->eof()?print "ok\n":print "\nnot ok 5\n",goto clear;
print "read() cannot read...       ";
!$fh->read(my $buf,1)?print "ok\n":print "\nnot ok 5\n",goto clear;

print "Position: $fh->{pos}\n";

print "Seeking to beginning of file in 1-byte-steps...\n";
for (1..length($string)) {
	print "Real position: ".(length($string)-$_)."\n";
	$fh->seek(-1,1);
	print "Position from tell(): ".$fh->tell()."... ";
	$fh->tell() == length($string)-$_?print "ok\n":print "\nnot ok 5\n",goto clear;
	print "eof() has to return false and returned '".$fh->eof()."'... ";
	!$fh->eof()?print "ok\n":print "\nnot ok 5\n",goto clear;
}

print "ok 5\n";

print "Reading 10000 Bytes (includes complete File)...\n";
my $file;
print $fh->read($file,10000)." bytes read. Comparing with original:\n";
print "Orig: $string\n";
print "Copy: $file\n";
$file eq $string?print "ok 6\n":print "not ok 6\n",goto clear;

$file='';
print "Seeking back to beginning of file, reading 2 x 5 bytes...\n";
$fh->seek(0,0);
print $fh->read($file,5)." bytes read for pass 1.\n";
print "Position is at ".$fh->tell()."... ";
$fh->tell() == 5?print "ok\n":print "\nnot ok 7\n",goto clear;
print $fh->read($file,5,5)." bytes appended for pass 2.\n";
$file eq $string?print "ok 7\n":print "not ok 7\n",goto clear;

$file='';
print "Seeking to 0 again, reading in 1-byte-steps until eof()...\n";
$fh->seek(0,0);
until ($fh->eof()) {
	my $char;
	print $fh->read($char,1)." byte read.\n";
	$file.=$char;
}
print "Orig: $string\n";
print "Copy: $file\n";
$string eq $file?print "ok 8\n":print "not ok 8\n",goto clear;

$file='';
print "Seeking to 0 again, reading in 3-byte-steps until eof()...\n";
$fh->seek(0,0);
until ($fh->eof()) {
	my $char;
	print $fh->read($char,3)." byte read.\n";
	$file.=$char;
}
print "Orig: $string\n";
print "Copy: $file\n";
$string eq $file?print "ok 9\n":print "not ok 9\n",goto clear;

print "Seeking to negative position out of range...\n";
$fh->seek(-10000,1)==0?print "ok 10\n":print "not ok 10\n",goto clear;

print "Seeking to positive position out of range...\n";
$fh->seek(10000,1)==length($string)?print"ok 11\n":print "not ok 11\n",goto clear;

print "What else should I test?\n\n";

for (1..4) {
    unlink "/tmp/IO-Multi-Test_$_";
}
exit;

clear:
for (1..4) {
	unlink "/tmp/IO-Multi-Test_$_";
}
die "Error, test aborted.\n";
