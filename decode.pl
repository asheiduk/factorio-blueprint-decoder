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

sub read_s8(*){
	my $fh = shift;
	read $fh, my $data, 1 or croak;
	return unpack "c", $data;
}

sub read_u16(*){
	my $fh = shift;
	read $fh, my $data, 2 or croak;
	return unpack "S<", $data;
}

sub read_s16(*){
	my $fh = shift;
	read $fh, my $data, 2 or croak;
	return unpack "s<", $data;
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
			$b == $expected or croak sprintf "expected 0x%02x but got 0x%02x at position 0x%x", $expected, $b, tell($fh)-1;
		}
	}
	else {
		my $expected = 0x00;
		my $b = read_u8($fh);
		$b == $expected or croak sprintf "expected 0x%02x but got 0x%02x at position 0x%x", $expected, $b, tell($fh)-1;
	}
}

sub read_ignore(*$){
	my $fh = shift;
	my $length = shift;

	read $fh, my ($data), $length;
	return $data;
}

sub read_count(*){
	my $fh = shift;
	return read_u8($fh);
}

################################################################

# maybe helpfull: https://wiki.factorio.com/Data_types
# maybe helpfull: https://wiki.factorio.com/Types/Position
sub read_delta_position(*){
	my $fh = shift;

	# lookahead
	my $byte = read_u8($fh);
	if( $byte == 0xff ){
		my $read_delta = sub() {
			my $fraction = read_u16($fh);
			my $integer = read_s16($fh);
			return $integer +  $fraction / 2**16;
		};
		my $delta_x = $read_delta->();
		my $delta_y = $read_delta->();
		read_unknown($fh); 		# TODO: strange thing...
		return ($delta_x, $delta_y);
	}
	else {
		# undo lookahead :-(
		$fh->ungetc($byte);
		my $read_delta = sub() {
			my $fraction = read_u8($fh);
			my $integer = read_s8($fh);
			return $integer +  $fraction / 2**8;
		};
		my $delta_x = $read_delta->();
		my $delta_y = $read_delta->();
		return ($delta_x, $delta_y);
	}
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
				# So far only "container/wooden chest" (0x0101) really needs two bytes.
				my $entry_id = read_u16($fh);
				my $entry_name = read_string($fh);
				printf "    [%d] %04x '%s'\n", $e, $entry_id, $entry_name;
				$result->{$cat_name."/".$entry_name} = $entry_id;
			}
		}
	}
	return $result;
}

sub read_blueprint(*$){
	my $fh = shift;
	my $library = shift;
	my $result = {};

	read_unknown($fh);
	$result->{label} = read_string($fh);
	printf "blueprint '%s'", $result->{label};

	
	# read_unknown($fh, 0x00, 0x00, 0xff, 0xa4, 0x02, 0x00, 0x00);
	read_ignore($fh, 7);
	
	$result->{version} = read_version($fh);
	
	read_unknown($fh);
	
	$result->{migrations} = read_migrations($fh);

	$result->{description} = read_string($fh);

	read_unknown($fh);


	my $entity_count = read_u16($fh);
	printf "entities: %d\n", $entity_count;
	
	read_unknown($fh, 0x00, 0x00);
	my ($last_x, $last_y) = (0, 0);
	for(my $e=0; $e<$entity_count; ++$e){
	
# 00000360        00 00 97 00 ff 7f  80 27 03 00 80 e9 04 00  |  .......'......|
# 00000370  20 00 06 04 00 00 00 00  00 00 00 00 97 00 00 00  | ...............|
#
# hints:
#
# 	97: inserter/inserter
# 	27 03: 807 (dec) x-position of first entity in export is 807.5
# 	e9 04: 1257(dec) y-position of first entity in export is 1257.5

		# type
		my $type_id = read_u16($fh);
		my $type_name = get_type_name($library, $type_id);

		# position
		my ($delta_x, $delta_y) = read_delta_position($fh);
		my ($x, $y) = ($last_x + $delta_x, $last_y + $delta_y);

		# maybe helpfull: https://wiki.factorio.com/Data_types
	 	## maybe helpfull: https://wiki.factorio.com/Types/Direction

#	 	read_ignore($fh, )

		read_unknown($fh, 0x20, 0x00, 0x06, 0x04);
		read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);

		printf "    [%d] x: %g, y: %g, '%s'\n", $e, $x, $y, $type_name;
		my $entity = {
			name => $type_name,
			position => {
				x => $x,
				y => $y
			}
		};
		push @{$result->{entities}}, $entity;

		($last_x, $last_y) = ($x, $y);

		#last;
	}

	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);

	my $icon_count = read_count($fh);
	if($icon_count>0){
		printf "icons: %s\n", $icon_count;
		my @icons;
		for(my $i=0; $i<$icon_count; ++$i){
			# TODO: The export format is more complex and mentions "type:item".
			read_unknown($fh);
			my $type_id = read_u16($fh);
			if($type_id == 0x00){
				printf "    [%d] (none)\n", $i;
				push @icons, undef;
			}
			else {
				my $type_name = get_type_name($library, $type_id);
				printf "    [%d] '%s' (%04x)\n", $i, $type_name, $type_id;
				push @icons, $type_name;
			}
		}
		$result->{icons} = \@icons;
	}

	return $result;
}

sub get_type_id($$){
	my $library = shift;
	my $key = shift;

	return $library->{types}{$key};
}

sub get_type_name($$){
	my $library = shift;
	my $wanted_id = shift;

	my $types = $library->{types};

	# TODO: this is expensive and excessive. Works for now.
	my @matches;
	while(my ($k, $v) = each %$types){
		if($v == $wanted_id){
			push @matches, $k;
		}
	}

	croak "ID $wanted_id is defined multiple times: @matches" if( @matches > 1 );
	croak "ID $wanted_id is not defined." unless (@matches);

	return shift @matches;
}

sub read_blueprint_library(*){
	my $fh = shift;
	my $result = {};

	$result->{version} = read_version($fh);
	read_unknown($fh);
	$result->{migrations} = read_migrations($fh);
	$result->{types} = read_types($fh);
	
	# TODO: unknown area
	read_ignore($fh, 21);

	for(my $b=0; $b<2; ++$b){
		my $type = read_u8($fh);
		if( $type == get_type_id($result, "blueprint/blueprint") ){
			push @{$result->{blueprints}}, read_blueprint($fh, $result);
		}
		else {
			croak "unexpected type: $type";
		}

		# TODO: unknown area
		read_ignore($fh, 11);
#		last;
	}
	
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
