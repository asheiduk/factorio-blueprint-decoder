#!/usr/bin/perl
use v5.26;
use strict;
use warnings;
use JSON;
use Carp;

# maybe helpfull: https://wiki.factorio.com/Data_types
# maybe helpfull: https://wiki.factorio.com/Types/Direction


################################################################
################################################################

package Index;
use v5.26;
use strict;
use warnings;
use Carp;

# value is the prototype-class (except "entity"). In BP exports the wording is just "virtual".
use constant {
	ITEM => "item",
	FLUID => "fluid",
	VSIGNAL => "virtual-signal",
	TILE => "tile",
	ENTITY => "entity"
};

my %_kind_mapping = (
	# item (0)
	ammo => ITEM,
	armor => ITEM,
	blueprint => ITEM,
	"blueprint-book" => ITEM,
	capsule => ITEM,
	"deconstruction-item" => ITEM,
	gun => ITEM,
	item => ITEM,
	"item-with-entity-data" => ITEM,
	module => ITEM,
	"spidertron-remote" => ITEM,
	"rail-planner" => ITEM,
	"repair-tool" => ITEM,
	tool => ITEM,
	"upgrade-item" => ITEM,
	# fluid (1)
	fluid => FLUID,
	# virtual-signal (2)
	"virtual-signal" => VSIGNAL,
	# entity
	accumulator => ENTITY,
	"arithmetic-combinator" => ENTITY,
	"artillery-wagon" => ENTITY,
	"assembling-machine" => ENTITY,
	beacon => ENTITY,
    boiler => ENTITY,
    "cargo-wagon" => ENTITY,
	"constant-combinator" => ENTITY,
    container => ENTITY,
    "curved-rail" => ENTITY,
    "decider-combinator" => ENTITY,
    "electric-pole" => ENTITY,
    "fluid-wagon" => ENTITY,
    furnace => ENTITY,
    generator => ENTITY,
	"heat-pipe" => ENTITY,
	"infinity-container" => ENTITY,
    inserter => ENTITY,
    lab => ENTITY,
    lamp => ENTITY,
    locomotive => ENTITY,
    "logistic-container" => ENTITY,
	pipe => ENTITY,
	"pipe-to-ground" => ENTITY,
	"power-switch" => ENTITY,
	"programmable-speaker" => ENTITY,
	pump => ENTITY,
	"rail-chain-signal" => ENTITY,
	"rail-signal" => ENTITY,
	reactor => ENTITY,
	roboport => ENTITY,
	"solar-panel" => ENTITY,
	splitter => ENTITY,
	"storage-tank" => ENTITY,
	"straight-rail" => ENTITY,
	"train-stop" => ENTITY,
	"transport-belt" => ENTITY,
	"underground-belt" => ENTITY,
	# tile
	tile => TILE,
);

sub new {
	my $class = shift;
	
	return bless {
		ITEM() => {},
		FLUID() => {},
		VSIGNAL() => {},
		TILE() => {},
		ENTITY() => {}
	}, $class
}

sub add($$$$$) {
	my $self = shift or croak;
	my $id = shift or croak;
	my $class = shift or croak;
	my $name = shift or croak;

	my $kind = $self->_map_class_to_kind($class);
	my $entry = $self->entry($kind, $class, $id);
	croak "ID $id is already used for $entry->{class}/$entry->{name}" if $entry;

	$self->{$kind}{$id} = {
		class => $class,
		name => $name,
		id => $id
	};
}

sub entry($$$$){
	my $self = shift or croak;
	my $kind = shift or croak;
	my $id = shift or croak;

	# avoid autovivification of $self->{$kind}{$id};
	my $entries = $self->{$kind};
	return undef unless $entries;
	return $entries->{$id};
}

sub name($$$) {
	my $self = shift or croak;
	my $kind = shift or croak;
	my $id = shift or croak;

	# avoid autovivification of $self->{$kind}{$id}{name};
	my $entry = $self->entry($kind, $id);
	return undef unless $entry;
	return $entry->{name};
}

sub id($$$$){
	my $self = shift or croak;
	my $kind = shift or croak;
	my $class = shift or croak;
	my $name = shift or croak;

	for my $v (values %{$self->{$kind}}){
		return $v->{id} if $v->{class} eq $class && $v->{name} eq $name;
	}
	return undef;
}

sub _map_class_to_kind($$){
	my $self = shift or croak;
	my $class = shift or croak;

	my $kind = $_kind_mapping{$class};
	croak "kind of class '$class' is unknown" unless $kind;
	return $kind;
}

sub TO_JSON($){
	my $self = shift or croak;

	my %copy = ( %$self );
	for(keys %copy){
		delete $copy{$_} unless %{$copy{$_}};
	}
	return \%copy;
}

################################################################
################################################################

package main;

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

sub read_count8(*){
# TODO: savety check for 0xff
	my $fh = shift;
	return read_u8($fh);
}

sub read_count16(*){
	my $fh = shift;
	return read_u16($fh);
}

sub read_count32(*){
	my $fh = shift;
	return read_u32($fh);
}

################################################################
#
# mid level parsing -- without Index

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
	
	my $count = read_count8($fh);
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
# mid level parsing -- with Index


sub read_type_and_name(*$){
	my $fh = shift;
	my $library = shift;
	
	my $kind_id = read_u8($fh);
	my $id = read_u16($fh);
	return undef unless $id;
	
	my $kind = (Index::ITEM, Index::FLUID, Index::VSIGNAL)[$kind_id];
	croak "unknown prototype kind $kind_id" unless $kind;

	my $type = ("item", "fluid", "virtual")[$kind_id];
	my $name = get_name($library, $kind, $id);

	return {
		type => $type,
		name => $name
	};
}

################################################################
#
# entity and entity-parts (ep_)
#

sub ep_direction(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;
	
	my $direction = read_u8($fh);
	if($direction != 0x00){
		$entity->{direction} = $direction;
	}
}

sub ep_circuit_connections(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	my $has_circuit_connections = read_bool($fh);
	if($has_circuit_connections){
		my %connections;

		# connections
		# TODO: how many "colors"? copper?
		# https://lua-api.factorio.com/latest/defines.html#defines.wire_type
		for my $color ("red", "green") {
			my @peers;
			# TODO: variable length for many connections?
			my $peer_count = read_count8($fh);
			for(my $p=0; $p<$peer_count; ++$p){
				push @peers, read_u32($fh);
				read_unknown($fh, 0x01, 0xff);
			}
			$connections{$color} = \@peers if @peers;
		}
		
		# TODO: The export has another dict with key '"1"' wegded
		# between "connections" and ("red"/"green"). Maybe circuit_connector_id
		# https://lua-api.factorio.com/latest/defines.html#defines.circuit_connector_id
		$entity->{connections} = \%connections if %connections;

		# TODO
		read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);

		# circuit condition & logistic condition
		my $parser = sub {
			my $condition_name = shift;
			my %condition;
			
			my $comparator_index = read_u8($fh); # default: 0x01
			my @comparators = (">", "<", "=", "≥", "≤", "≠"); 	# same order in drop-down
			my $comparator = $comparators[$comparator_index];
			croak "unexpected comparator index 0x%02x", $comparator_index unless $comparator;

			my $first_signal = read_type_and_name($fh, $library);
			my $second_signal = read_type_and_name($fh, $library);

			my $constant = read_s32($fh);
			my $use_constant = read_bool($fh);

			# hide "default" condition
			if($first_signal || $comparator ne "<" || $second_signal || $constant){
				$condition{first_signal} = $first_signal;
				$condition{comparator} = $comparator;
				# The export does not output data if it is hidden in the UI.
				if($use_constant){
					$condition{constant} = $constant;
				}
				else {
					$condition{second_signal} = $second_signal;
				}
			}
			
			$entity->{control_behavior}{$condition_name} = \%condition if %condition;
			
		};

		$parser->("circuit_condition");
		$parser->("logistic_condition");
		my $logistic_connected = read_bool($fh);
		if($logistic_connected){
			$entity->{control_behavior}{connect_to_logistic_network} = JSON::true;
		}
		else {
			delete $entity->{control_behavior}{logistic_condition};
		}
		
		read_unknown($fh, 0x00, 0x00);

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
		my $stack_size_signal = read_type_and_name($fh, $library);
		if($stack_size_signal){
			$entity->{control_behavior}{stack_control_input_signal} = $stack_size_signal;
		}
	}
}

sub ep_filters(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	# Even without filters the count is > 0 for filter-inserters.
	my $filter_count = read_count8($fh);
	if($filter_count > 0){
		my @filters;
		for(my $f=0; $f<$filter_count; ++$f){
			my $filter_id = read_u16($fh);
			if($filter_id != 0x00){
				my $filter_name = get_name($library, Index::ITEM, $filter_id);
				push @filters, $filter_name;
			}
			else {
				push @filters, undef;
			}
		}
		$entity->{filters} = \@filters;
		# TODO: The export file suppresses an empty list (or a list with only undef entries).
		# TODO: The export also uses a map, not an array, hence the items have an additional index field.
	}
}

# parameter:
# - $fh
# - $library
# - entity_index
# - $offset_x
# - $offset_y
sub read_entity(*$$$$){
	my $fh = shift;
	my $library = shift;
	my $entity_index = shift;
	my $last_x = shift;
	my $last_y = shift;

	my $file_offset = tell($fh);
		
	# type
	my $type_id = read_u16($fh);
	my $type_name = get_name($library, Index::ENTITY, $type_id);

	# position
	my ($delta_x, $delta_y) = read_delta_position($fh);
	my ($x, $y) = ($last_x + $delta_x, $last_y + $delta_y);

	printf "    [%d] \@%04x - x: %g, y: %g, '%s'\n", $entity_index, $file_offset, $x, $y, $type_name;
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

	# entity ids
	if($flags1 & 0x10){
		my @entity_ids;
		# TODO: perhaps the "count" is not a count a kind of type like the type
		# before signal ids in circuit conditions? But 0x01 would be "fluid".
		my $id_count = read_count8($fh);
		for(my $i=0; $i<$id_count; ++$i){
			push @entity_ids, read_u32($fh);
		}
		$entity->{entity_ids} = \@entity_ids;
		printf "\tentity-ids: %s\n", join(", ", @entity_ids);
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
	ep_direction($fh, $entity, $library);

	# override stack size
	if($flags2 & 0x01){
		$entity->{override_stack_size} = read_u8($fh);
	}

	# circuit network connections
	ep_circuit_connections($fh, $entity, $library);

	# item filters
	ep_filters($fh, $entity, $library);
	unless($flags2 & 0x02){
		$entity->{filter_mode} = "blacklist";
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
	
	my $entity_count = read_count32($fh);
	printf "entities: %d\n", $entity_count;
	my ($last_x, $last_y) = (0, 0);
	for(my $e=0; $e<$entity_count; ++$e){
		my $entity = read_entity($fh, $library, $e, $last_x, $last_y);
		my %position = %{$entity->{position}};

		push @{$result->{entities}}, $entity;
		$last_x = $position{x};
		$last_y = $position{y};
	}

	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);

	my $icon_count = read_count8($fh);
	if($icon_count>0){
		printf "icons: %s\n", $icon_count;
		my @icons;
		for(my $i=0; $i<$icon_count; ++$i){
			my $icon = read_type_and_name($fh, $library);
			if($icon){
				printf "    [%d] '%s' / '%s'\n", $i, $icon->{type}, $icon->{name};
				push @icons, $icon;
			}
			else {
				printf "    [%d] (none)\n", $i;
				push @icons, undef;
			}
		}
		$result->{icons} = \@icons;
	}

	return $result;
}

################################################################
#
# blueprint library

sub read_prototype_ids(*){
	my $fh = shift;
	my $result = Index->new;
	
	my $class_count = read_count16($fh);
	printf "used prototype classes: %d\n", $class_count;
	for(my $c=0; $c<$class_count; ++$c){
	
		my $class_name = read_string($fh);
		my $proto_count = read_count8($fh);
		
		if( $class_name eq "tile" ){		# TODO: strange exception
			printf "    [%d] class '%s' - entries: %d\n", $c, $class_name, $proto_count;
			for(my $p=0; $p<$proto_count; ++$p){
				my $proto_id = read_u8($fh);
				my $proto_name = read_string($fh);
				printf "        [%d] %02x '%s'\n", $p, $proto_id, $proto_name;
				$result->add($proto_id, $class_name, $proto_name);
#				$result->{$kind_name."/".$proto_name} = $proto_id;
			}
		}
		else {
			printf "    [%d] class '%s' - entries: %d\n", $c, $class_name, $proto_count;
			read_unknown($fh); 		# TODO: another strange exception: data between count and list
			for(my $p=0; $p<$proto_count; ++$p){
				my $proto_id = read_u16($fh);
				my $proto_name = read_string($fh);
				printf "        [%d] %04x '%s'\n", $p, $proto_id, $proto_name;
				$result->add($proto_id, $class_name, $proto_name);
#				$result->{$cat_name."/".$entry_name} = $entry_id;
			}
		}
	}
	return $result;
}

# TODO: move to index XOR inline?
sub get_item_id($$$){
	my $library = shift or croak;
	my $class = shift or croak;
	my $name = shift or croak;

	my $result = $library->{prototypes}->id(Index::ITEM, $class, $name);
	croak sprintf "##### unknown item name: %s, %s", $class, $name unless $result;
	return $result;
}

# TODO: move to index XOR inline?
sub get_name($$$){
	my $library = shift or croak;
	my $kind = shift or croak;
	my $id = shift or croak;

	my $result = $library->{prototypes}->name($kind, $id);
	croak sprintf "##### unknown thing: kind: %s, id: %04x", $kind, $id unless $result;
	return $result;
}

sub read_blueprint_library(*){
	my $fh = shift;
	my $result = {};

	$result->{version} = read_version($fh);
	read_unknown($fh);
	$result->{migrations} = read_migrations($fh);
	$result->{prototypes} = read_prototype_ids($fh);

	read_unknown($fh, 0x00, 0x00);
	read_ignore($fh, 1); # a small generation/save/copy counter?
	read_unknown($fh, 0x00, 0x00, 0x00);
	read_ignore($fh, 4); # u32 unix timestamp
	read_unknown($fh, 0x01);
	
	my $blueprint_count = read_count16($fh);
	printf "\nblueprints: %d\n", $blueprint_count;
	read_unknown($fh, 0x00, 0x00);

	my $blueprint_id = get_item_id($result, "blueprint", "blueprint");
	for(my $b=0; $b<$blueprint_count; ++$b){
		my $is_used = read_bool($fh);

		if($is_used){
			printf "\n[%d] library slot: used\n", $b;
			read_ignore($fh, 5); 	# perhaps some generation counter?
			my $type = read_u16($fh);
			if($type == $blueprint_id){
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
print to_json($library, {pretty => 1, convert_blessed => 1, canonical => 1});
dump_trailing_data($fh);
close($fh);
