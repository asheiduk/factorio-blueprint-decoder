#!/usr/bin/perl
use v5.26.1;
use strict;
use warnings;
use Carp;


################################################################

sub read_u8(*){
	my $fh = shift;
	read $fh, my $data, 1 or croak;
	return unpack "C", $data;
}

sub read_u16(*){
	my $fh = shift;
	read $fh, my $data, 2 or croak;
	return unpack "v", $data;
}

sub read_string(*){
	my $fh = shift;
	my $length = read_u8($fh);
	read $fh, my ($data), $length;
	return $data;
}

sub read_unknown(*;$){
	my $fh = shift;
	my $expected = shift // 0x00;
	my $b = read_u8($fh);
	$b == $expected or croak;
}

sub read_count(*){
	my $fh = shift;
	return read_u8($fh);
}

################################################################

sub read_version(*){
	my $fh = shift;
	my ($main, $major, $minor, $developer) = (read_u16($fh), read_u16($fh), read_u16($fh),read_u16($fh));
	return ($main, $major, $minor, $developer);
}

sub read_migrations(*){
	my $fh = shift;
	my $count = read_count($fh);
	printf "migrations: %d\n", $count;
	for(my $i=0; $i<$count; ++$i){
		my $mod_name = read_string($fh);
		my $mod_migration = read_string($fh);
		printf "[%d] mod '%s', migration '%s'\n", $i, $mod_name, $mod_migration;
	}
}

sub read_x(*){
	my $fh = shift;
	my $x_count = read_u16($fh);
	printf "categories (?): %d\n", $x_count;
	for(my $x=0; $x<$x_count; ++$x){
		my $s1 = read_string($fh);
		my $y_count = read_count($fh);
		my $bx = read_u8($fh);
		printf "[%d] category '%s': %d items, info: %02x\n", $x, $s1, $y_count, $bx;

		if( $bx == 0 ){
			for(my $y=0; $y<$y_count; ++$y){
				my $id = read_u8($fh);
				my $b = read_u8($fh); 	# ??? (seldom used)
				my $s2 = read_string($fh);
				printf "[%d, %d] %02x %02x '%s'\n", $x, $y, $id, $b, $s2;
			}
		}
		elsif( $bx == 2 ){
			for(my $y=0; $y<$y_count; ++$y){
				my $b = read_u8($fh); 	# ???
				my $s2 = read_string($fh);
				printf "[%d, %d] %02x '%s'\n", $x, $y, $b, $s2;
			}
			my $s3 = read_string($fh);
			printf "\tadditional category data: '%s'\n", $s3;
		}
		else {
			croak;
		}
		

	}
}

sub dump_blueprint_library(*){
	my $fh = shift;
	my ($main_version, $major_version, $minor_version, $developer_version) = read_version($fh);
	printf "version: %d.%d.%d.%d\n", $main_version, $major_version, $minor_version, $developer_version;
	
	read_unknown($fh);
	read_migrations($fh);
	read_x($fh);
}


my $file = $ARGV[0] || "blueprint-storage.dat";
printf "file: %s\n", $file;
open(my $fh, "<", $file) or die;
dump_blueprint_library($fh);
close($fh);
