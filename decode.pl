#!/usr/bin/perl
use v5.26.1;
use strict;
use warnings;
use Data::Dumper;
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

sub read_unknown(*@){
	my $fh = shift;
	if( @_ ){
		for my $expected (@_) {
			my $b = read_u8($fh);
#			printf "# exp: %02x, read: %02x\n", $expected, $b;
			$b == $expected or croak sprintf "expected 0x%02x but got 0x%02x", $expected, $b;
		}
	}
	else {
		my $expected = 0x00;
		my $b = read_u8($fh);
		$b == $expected or croak sprintf "expected 0x%02x but got 0x%02x", $expected, $b;
	}
}

sub read_count(*){
	my $fh = shift;
	return read_u8($fh);
}

################################################################

sub read_version(*){
	my $fh = shift;
	my ($main, $major, $minor, $developer) = (read_u16($fh), read_u16($fh), read_u16($fh),read_u16($fh));
	printf "version: %d.%d.%d.%d\n", $main, $major, $minor, $developer;
	return {
		main => $main,
		major => $major,
		minor => $minor,
		developer => $developer
	};
}

sub read_migrations(*){
	my $fh = shift;
	my $result = [];
	
	my $count = read_count($fh);
	printf "migrations: %d\n", $count;
	for(my $i=0; $i<$count; ++$i){
		my $mod_name = read_string($fh);
		my $migration_file = read_string($fh);
		printf "[%d] mod '%s', migration '%s'\n", $i, $mod_name, $migration_file;
		push @$result, { mod_name => $mod_name, migration_file => $migration_file }
	}
	return $result;
}

sub read_types(*){
	my $fh = shift;
	my $result = {};
	
	my $cat_count = read_u16($fh);
	printf "categories: %d\n", $cat_count;
	for(my $c=0; $c<$cat_count; ++$c){
	
		my $cat_name = read_string($fh);
		my $entry_count = read_count($fh);
		
		if( $cat_name eq "tile" ){		# TODO: strange exception
			printf "[%d] category '%s' - entries: %d\n", $c, $cat_name, $entry_count;
			for(my $e=0; $e<$entry_count; ++$e){
				my $entry_id = read_u8($fh);
				my $entry_name = read_string($fh);
				printf "    [%d] %02x '%s'\n", $e, $entry_id, $entry_name;
				$result->{$cat_name."/".$entry_name} = $entry_id;
			}

			# 000001a0                 04 74 69  6c 65 07 02 08 63 6f 6e  |     .tile...con|
			# 000001b0  63 72 65 74 65 03 14 68  61 7a 61 72 64 2d 63 6f  |crete..hazard-co|
			# 000001c0  6e 63 72 65 74 65 2d 6c  65 66 74 04 15 68 61 7a  |ncrete-left..haz|
			# 000001d0  61 72 64 2d 63 6f 6e 63  72 65 74 65 2d 72 69 67  |ard-concrete-rig|
			# 000001e0  68 74 05 10 72 65 66 69  6e 65 64 2d 63 6f 6e 63  |ht..refined-conc|
			# 000001f0  72 65 74 65 06 1c 72 65  66 69 6e 65 64 2d 68 61  |rete..refined-ha|
			# 00000200  7a 61 72 64 2d 63 6f 6e  63 72 65 74 65 2d 6c 65  |zard-concrete-le|
			# 00000210  66 74 07 1d 72 65 66 69  6e 65 64 2d 68 61 7a 61  |ft..refined-haza|
			# 00000220  72 64 2d 63 6f 6e 63 72  65 74 65 2d 72 69 67 68  |rd-concrete-righ|
			# 00000230  74 08 08 6c 61 6e 64 66  69 6c 6c                 |t..landfill     |

			# tokens: "tile", 07, 02, "concrete", 03, "hazard-concrete-left", 04 "hazard-concrete-right",
			# 	05, "refined-concrete", 06, "refined-hazard-concrete-left", 07, "refined-hazard-concrete-right",
			# 	08, "landfill"
			
		}
		else {
			printf "[%d] category '%s' - entries: %d\n", $c, $cat_name, $entry_count;
			read_unknown($fh);
			for(my $e=0; $e<$entry_count; ++$e){
				my $entry_id = read_u8($fh);
				my $b2 = read_u8($fh); 	# only(?) example: 01 01 container/wooden-chest
				my $entry_name = read_string($fh);
				printf "    [%d] %02x %02x '%s'\n", $e, $entry_id, $b2, $entry_name;
				$result->{$cat_name."/".$entry_name} = $entry_id;
				if( $b2 != 0 && ( $cat_name ne "container" || $entry_name ne "wooden-chest") ){
					croak "unexpected/new example of unknown data in category entry: $cat_name, $entry_name, $entry_id: $b2";
				}
			}
		}
	}
	return $result;
}

sub read_blueprint_library(*){
	my $fh = shift;
	my $result = {};

	$result->{version} = read_version($fh);
	read_unknown($fh);
	$result->{migrations} = read_migrations($fh);
	$result->{types} = read_types($fh);

	return $result;
}

sub dump_trailing_data(*){
	my $fh = shift;
	my ($count, $data);

	$count = read $fh, $data, 1;
	if( $count > 0 ){
		printf "unparsed data:\n";
		while( $count > 0 ){
			printf "%02x ", unpack("C", $data);
			$count = read $fh, $data, 1;
		}
		printf "\n";
	}
}


my $file = $ARGV[0] || "blueprint-storage.dat";
printf "file: %s\n", $file;
open(my $fh, "<", $file) or die;
my $library = read_blueprint_library($fh);
print Dumper($library);
dump_trailing_data($fh);
close($fh);
