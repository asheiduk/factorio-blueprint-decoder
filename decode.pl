#!/usr/bin/perl
use v5.26.1;
use strict;
use warnings;
use JSON;
use Carp;

# maybe helpfull: https://wiki.factorio.com/Data_types
# maybe helpfull: https://wiki.factorio.com/Types/Direction


################################################################
#
# low level parsing like primitves

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

sub read_u32(*){
	my $fh = shift;
	read $fh, my $data, 4 or croak;
	return unpack "L<", $data;
}

sub read_s32(*){
	my $fh = shift;
	read $fh, my $data, 4 or croak;
	return unpack "l<", $data;
}

sub read_bool(*){
	my $fh = shift;
	my $b = read_u8($fh);
	croak sprintf "invalid boolean value %02x at position 0x%04x", $b, tell($fh)-1 unless $b == 0x00 || $b == 0x01;
	return $b == 0x01;
}

sub read_string(*){
	my $fh = shift;
	my $length = read_u8($fh);
	if($length == 0xff){
		$length = read_u32($fh);
	}
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

	my $file_position = tell($fh);
	read $fh, my ($data), $length;

	printf "#\tignored @%04x: %s\n",
		$file_position, join " ",
		map{ sprintf "%02x", $_ } unpack "C*", $data;
	
	return $data;
}

sub read_count(*){
	my $fh = shift;
	return read_u8($fh);
}

################################################################
#
# mid level parsing

# maybe helpfull: https://wiki.factorio.com/Version_string_format
sub read_version(*){
	my $fh = shift;
	my @result;
	for(1..4){
		push @result, read_u16($fh);
	}
	printf "version: %s\n", join ".", @result;
	return \@result;
}

sub read_migrations(*){
	my $fh = shift;
	my $result = [];
	
	my $count = read_count($fh);
	printf "migrations: %d\n", $count;
	for(my $i=0; $i<$count; ++$i){
		my $mod_name = read_string($fh);
		my $migration_file = read_string($fh);
		printf "    [%d] mod '%s', migration '%s'\n", $i, $mod_name, $migration_file;
		push @$result, { mod_name => $mod_name, migration_file => $migration_file }
	}
	return $result;
}

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
#
# entity and entity-parts
#

# parameter:
# - $fh
# - $library
# - $offset_x
# - $offset_y
sub read_entity(*$$$){
	my $fh = shift;
	my $library = shift;
	my $last_x = shift;
	my $last_y = shift;

	# type
	my $type_id = read_u16($fh);
	my $type_name = get_type_name($library, $type_id);

	# position
	my ($delta_x, $delta_y) = read_delta_position($fh);
	my ($x, $y) = ($last_x + $delta_x, $last_y + $delta_y);

	my $entity = {
		name => $type_name,
		position => {
			x => $x,
			y => $y
		}
	};
	
	read_unknown($fh, 0x20);

	my $flags1 = read_u8($fh);
	# 0x10	-- has entity id (default=0)
	if( ($flags1|0x10) != 0x10 ){
		croak sprintf "unexpected flags1 %02x at postion 0x%x", $flags1, tell($fh)-1;
	}
	
	if($flags1 & 0x10){
		my @entity_id;
		my $id_count = read_u8($fh);
		for(my $i=0; $i<$id_count; ++$i){
			push @entity_id, read_u32($fh);
		}
		$entity->{entity_ids} = \@entity_id;
		# TODO: in export "entity_"number" but "entity_id" in references.
		# Also: EACH entity in the export has the number and entities are
		# numbered 1..N. And there is only one - not an array.
	}

	my $flags2 = read_u8($fh);
	# 0x01 -- override_stack_size
	# 0x02 -- filter_mode: 0=blacklist, 1(default)=whitelist
	# 0x04 -- TODO - unknown - default=1(?)
	# others: TODO - unknown - default=0(?)
	if( ($flags2|0x03) != 0x07 ){
		croak sprintf "unexpected flags2 %02x at position 0x%x", $flags2, tell($fh)-1;
	}
	
	# direction
	my $direction = read_u8($fh);
	if($direction != 0x00){
		$entity->{direction} = $direction;
	}

	# override stack size
	if($flags2 & 0x01){
		$entity->{override_stack_size} = read_u8($fh);
	}

	# circuit network connections
	my $has_circuit_connections = read_bool($fh);
	if($has_circuit_connections){
		my %connections;

		# connections
		# TODO: how many "colors"? copper?
		# https://lua-api.factorio.com/latest/defines.html#defines.wire_type
		for my $color ("red", "green") {
			my @peers;
			# TODO: variable length for many connections?
			my $peer_count = read_u8($fh);
			for(my $p=0; $p<$peer_count; ++$p){
				push @peers, read_u32($fh);
				read_unknown($fh, 0x01, 0xff);
			}
			$connections{$color} = \@peers if @peers;
		}
		
		# TODO: The export has another dict with key '"1"' wegded
		# between "connections" and ("red"/"green"). Maybe circuit_connector_id
		# https://lua-api.factorio.com/latest/defines.html#defines.circuit_connector_id
		$entity->{connections} = \%connections;

		# TODO
		read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);

		# circuit condition
		{
			my %circuit_condition;
			
			my $comparator_index = read_u8($fh); # default: 0x01
			read_unknown($fh);
			my @comparators = (">", "<", "=", "≥", "≤", "≠"); 	# same order in drop-down
			my $comparator = $comparators[$comparator_index];
			croak "unexpected comparator index 0x%02x", $comparator_index unless $comparator;

			my $first_signal_id = read_u16($fh);
			my $first_signal_name = get_type_name($library, $first_signal_id) if $first_signal_id;
			read_unknown($fh);
			my $second_signal_id = read_u16($fh);
			my $second_signal_name = get_type_name($library, $second_signal_id) if $second_signal_id;
			my $constant = read_s32($fh);
			my $use_constant = read_bool($fh);

			# hide "default" condition
			if($first_signal_name || $comparator ne "<" || $second_signal_name || $constant){
				$circuit_condition{first_signal} = $first_signal_name;
				$circuit_condition{comparator} = $comparator;
				# The export does not output data if it is hidden in the UI.
				if($use_constant){
					$circuit_condition{constant} = $constant;
				}
				else {
					$circuit_condition{second_signal} = $second_signal_name;
				}
			}
			
			$entity->{control_behavior}{circuit_condition} = \%circuit_condition if %circuit_condition;
		}

		read_unknown($fh, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
		read_unknown($fh, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00);

		# maybe helpfull: https://lua-api.factorio.com/latest/defines.html#defines.control_behavior
		# TODO: Wiki inidcates, that this is more complicated!
		my $mode_of_operation = read_u8($fh);
		$entity->{control_behavior}{circuit_mode_of_operation} = $mode_of_operation if $mode_of_operation;

		my $read_hand_flag = read_bool($fh);
		my $read_hand_mode_hold = read_bool($fh);
		$entity->{control_behavior}{circuit_read_hand_contents} = JSON::true if $read_hand_flag;
		$entity->{control_behavior}{circuit_hand_read_mode} = 1 if $read_hand_mode_hold;

		my $set_stack_size = read_bool($fh);
		$entity->{control_behavior}{circuit_set_stack_size} = JSON::true if $set_stack_size;
		read_unknown($fh);
		my $stack_size_signal_id = read_u16($fh);
		if($stack_size_signal_id){
			my $signal_name = get_type_name($library, $stack_size_signal_id);
			$entity->{control_behavior}{stack_control_input_signal} = $signal_name;
		}
	}


	# item filters
	my $filter_count = read_u8($fh);
	if($filter_count > 0){
		my @filters;
		for(my $f=0; $f<$filter_count; ++$f){
			my $filter_id = read_u16($fh);
			if($filter_id != 0x00){
				my $filter_name = get_type_name($library, $filter_id);
				push @filters, $filter_name;
			}
			else {
				push @filters, undef;
			}
		}
		unless($flags2 & 0x02){
			$entity->{filter_mode} = "blacklist";
		}
		
		$entity->{filters} = \@filters;
	}
	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);

	return $entity;
}

################################################################
#
# blueprint

sub read_blueprint(*$){
	my $fh = shift;
	my $library = shift;
	my $result = {};

	my $file_position = tell($fh);
	
	$result->{label} = read_string($fh);
	printf "blueprint '%s' (@%04x)\n", $result->{label}, $file_position;

	read_unknown($fh, 0x00, 0x00, 0xff);
	read_ignore($fh, 4); 	# maybe some offset (with previous 0xff an flexible u8/u32 length?)
	
	$result->{version} = read_version($fh);
	
	read_unknown($fh);
	
	$result->{migrations} = read_migrations($fh);

	$result->{description} = read_string($fh);

	my $snap_to_grid = read_bool($fh);
	if($snap_to_grid){
		my $x = read_u32($fh);
		my $y = read_u32($fh);
		$result->{"snap-to-grid"} = {
			x => $x,
			y => $y
		};
		
		my $absolute_snapping = read_bool($fh);
		$result->{"absolute-snapping"} = JSON::true if $absolute_snapping;
	}
	
	my $entity_count = read_u32($fh);
	printf "entities: %d\n", $entity_count;
	my ($last_x, $last_y) = (0, 0);
	for(my $e=0; $e<$entity_count; ++$e){

		my $file_offset = tell($fh);

		my $entity = read_entity($fh, $library, $last_x, $last_y);
		my %position = %{$entity->{position}};
		my $type_name = $entity->{name};
		printf "    [%d] \@%04x - x: %g, y: %g, '%s'\n", $e, $file_offset, @position{"x", "y"}, $type_name;

		push @{$result->{entities}}, $entity;
		$last_x = $position{x};
		$last_y = $position{y};
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

################################################################
#
# blueprint library

sub read_types(*){
	my $fh = shift;
	my $result = {};
	
	my $cat_count = read_u16($fh);
	printf "categories: %d\n", $cat_count;
	for(my $c=0; $c<$cat_count; ++$c){
	
		my $cat_name = read_string($fh);
		my $entry_count = read_count($fh);
		
		if( $cat_name eq "tile" ){		# TODO: strange exception
			printf "    [%d] category '%s' - entries: %d\n", $c, $cat_name, $entry_count;
			for(my $e=0; $e<$entry_count; ++$e){
				my $entry_id = read_u8($fh);
				my $entry_name = read_string($fh);
				printf "        [%d] %02x '%s'\n", $e, $entry_id, $entry_name;
				$result->{$cat_name."/".$entry_name} = $entry_id;
			}
		}
		else {
			printf "    [%d] category '%s' - entries: %d\n", $c, $cat_name, $entry_count;
			read_unknown($fh);
			for(my $e=0; $e<$entry_count; ++$e){
				# So far only "container/wooden chest" (0x0101) really needs two bytes.
				my $entry_id = read_u16($fh);
				my $entry_name = read_string($fh);
				printf "        [%d] %04x '%s'\n", $e, $entry_id, $entry_name;
				$result->{$cat_name."/".$entry_name} = $entry_id;
			}
		}
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
	
	read_ignore($fh, 11);
	my $blueprint_count = read_u16($fh);
	printf "\nblueprints: %d\n", $blueprint_count;
	read_unknown($fh, 0x00, 0x00);

	for(my $b=0; $b<$blueprint_count; ++$b){
		my $is_used = read_bool($fh);

		if($is_used){
			printf "\n[%d] library slot: used\n", $b;
			read_ignore($fh, 5); 	# perhaps some generation counter?
			
			my $type = read_u16($fh);
			if( $type == get_type_id($result, "blueprint/blueprint") ){
				push @{$result->{blueprints}}, read_blueprint($fh, $result);
			}
			else {
				croak sprintf "unexpected type: %04x", $type;
			}
			
		}
		else {
			printf "\n[%d] library slot: free\n", $b;
		}
	}
	
	return $result;
}

################################################################
#
# main

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
print to_json($library, {pretty => 1, canonical => 1});
dump_trailing_data($fh);
close($fh);
