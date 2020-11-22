#!/usr/bin/perl
use v5.26;
use strict;
use warnings;
use JSON;
use Carp;
use POSIX qw(strftime);

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
	ENTITY => "entity",
	RECIPE => "recipe",
};

my %_kind_mapping = (
	# item
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
	# fluid
	fluid => FLUID,
	# virtual-signal
	"virtual-signal" => VSIGNAL,
	# entity
	accumulator => ENTITY,
	"ammo-turret" => ENTITY,
	"arithmetic-combinator" => ENTITY,
	"artillery-turret" => ENTITY,
	"artillery-wagon" => ENTITY,
	"assembling-machine" => ENTITY,
	beacon => ENTITY,
    boiler => ENTITY,
    "cargo-wagon" => ENTITY,
    cliff => ENTITY,
	"constant-combinator" => ENTITY,
    container => ENTITY,
    "curved-rail" => ENTITY,
    "decider-combinator" => ENTITY,
    "electric-pole" => ENTITY,
    "electric-turret" => ENTITY,
    "entity-ghost" => ENTITY,
    fish => ENTITY,
    "fluid-turret" => ENTITY,
    "fluid-wagon" => ENTITY,
    furnace => ENTITY,
    gate => ENTITY,
    generator => ENTITY,
	"heat-pipe" => ENTITY,
	"infinity-container" => ENTITY,
    inserter => ENTITY,
    "item-entity" => ENTITY,
    "item-request-proxy" => ENTITY,
    lab => ENTITY,
    lamp => ENTITY,
    "land-mine" => ENTITY,
    locomotive => ENTITY,
    "logistic-container" => ENTITY,
    "mining-drill" => ENTITY,
    "offshore-pump" => ENTITY,
	pipe => ENTITY,
	"pipe-to-ground" => ENTITY,
	"power-switch" => ENTITY,
	"programmable-speaker" => ENTITY,
	pump => ENTITY,
	radar => ENTITY,
	"rail-chain-signal" => ENTITY,
	"rail-signal" => ENTITY,
	reactor => ENTITY,
	roboport => ENTITY,
	"rocket-silo" => ENTITY,
	"simple-entity" => ENTITY,
	"solar-panel" => ENTITY,
	splitter => ENTITY,
	"storage-tank" => ENTITY,
	"straight-rail" => ENTITY,
	"tile-ghost" => ENTITY,
	"train-stop" => ENTITY,
	"transport-belt" => ENTITY,
	tree => ENTITY,
	"underground-belt" => ENTITY,
	"wall" => ENTITY,
	# tile
	tile => TILE,
	# recipe
	recipe => RECIPE,
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

sub ep_entity_ids(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;
	
	my $flags1 = read_u8($fh);
	# 0x10	-- has entity id (default=0)
	if( ($flags1|0x10) != 0x10 ){
		croak sprintf "unexpected flags1 %02x at postion 0x%x", $flags1, tell($fh)-1;
	}
	
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
}

sub ep_bar(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	my $bar = read_u8($fh);
	# The export format suppresses the default values. But these
	# are - in general - unknown to me beyond the vanilla chests.
	my %bar_defaults = (
		# container
		"wooden-chest" => 0x10,
		"iron-chest"   => 0x20,
		"steel-chest"  => 0x30,
		# logistic-container
		"logistic-chest-active-provider"	=> 0x30,
		"logistic-chest-passive-provider"	=> 0x30,
		"logistic-chest-storage"	=> 0x30,
		"logistic-chest-requester"	=> 0x30,
		"logistic-chest-buffer"		=> 0x30,
		# cheat mode
		"infinity-chest" => 0x30,
	);
	my $default_bar = $bar_defaults{$entity->{name}};
	if( not defined $default_bar or $default_bar != $bar){
		$entity->{bar} = $bar;
	}
}

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

	my %connections;

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
}

sub ep_conditions(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;
	
	# circuit condition & logistic condition
	my $parser = sub {
		my $condition_name = shift;
		my %condition;
		
		my $comparator_index = read_u8($fh); # default: 0x01
		my @comparators = (">", "<", "=", "≥", "≤", "≠"); 	# same order in drop-down
		my $comparator = $comparators[$comparator_index];
		croak sprintf "unexpected comparator index 0x%02x", $comparator_index unless $comparator;

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
}

sub ep_mode_of_operation_inserter(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

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

sub ep_modules(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	# Interesting point: Modules are not a simple list like icons.
	# Instead the modules are first sorted and then grouped by type.
	# So building an assembler with modules Eff1, Sp1, Eff1, Sp1 the blueprint
	# only contains only the data "Sp1: 2, Eff:2". So some details are omitted.
	
	my %items;
	my $item_count = read_count32($fh);
	for(my $i=0; $i<$item_count; ++$i){
		my $item_id = read_u16($fh);
		my $item_name = get_name($library, Index::ITEM, $item_id);
		my $item_count = read_u32($fh);
		$items{$item_name} = $item_count;
	}
	$entity->{items} = \%items if %items;
}

sub read_entity_inserter_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	# entity ids
	ep_entity_ids($fh, $entity, $library);
	
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
	my $has_circuit_connections = read_bool($fh);
	if($has_circuit_connections){
		# connections
		ep_circuit_connections($fh, $entity, $library);
		
		# circuit condition & logistic condition
		ep_conditions($fh, $entity, $library);
		read_unknown($fh, 0x00, 0x00);

		# mode of operation
		ep_mode_of_operation_inserter($fh, $entity, $library);
	}
	
	# item filters
	ep_filters($fh, $entity, $library);
	unless($flags2 & 0x02){
		$entity->{filter_mode} = "blacklist";
	}
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_entity_constant_combinator_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;
	
	# entity ids
	ep_entity_ids($fh, $entity, $library);

	# circuit connection
	ep_circuit_connections($fh, $entity, $library);
	
	my $filter_count = read_count32($fh);
	if($filter_count > 0){
		my @filters;
		for(my $f=0; $f<$filter_count; ++$f){
			my $signal = read_type_and_name($fh, $library);
			my $count = read_s32($fh);
			if($signal){
				push @filters, {
					signal => $signal,
					count => $count
				};
			}
			else {
				push @filters, undef;
			}
		}
		# Export: Why "filter"? These are not filters.
		# TODO: suppress empty signal list.
		$entity->{control_behavior}{filters} = \@filters;
	}

	my $is_on = read_bool($fh);
	unless($is_on){
		$entity->{control_behavior}{is_on} = JSON::false;
	}
	ep_direction($fh, $entity, $library);
	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_entity_container_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;
	
	# entity ids
	ep_entity_ids($fh, $entity, $library);

	# restriction aka. "bar"
	ep_bar($fh, $entity, $library);
	
	read_unknown($fh, 0x00);

	# circuit connection
	my $has_connections = read_bool($fh);
	if($has_connections){
		ep_circuit_connections($fh, $entity, $library);
	}
	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_entity_logistic_container_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;
	
	# entity ids
	ep_entity_ids($fh, $entity, $library);

	# restriction aka. "bar"
	ep_bar($fh, $entity, $library);
	
	read_unknown($fh, 0x00, 0x00);

	read_unknown($fh, 0x01);
	my $mode = read_u8($fh); 	# not used in export
	croak "unknown logistic mode $mode" if($mode<1 || $mode>5);
	read_unknown($fh, 0x03);
	my @request_filters;
	my $filter_count = read_count8($fh);
	for(my $f=0; $f<$filter_count; ++$f){
		my $item_id = read_u16($fh);
		my $item_count = read_u32($fh);
		read_unknown($fh);
		if($item_id){
			my $item_name = get_name($library, Index::ITEM, $item_id);
			push @request_filters, {
				name => $item_name,
				count => $item_count
			};
		}
		else {
			push @request_filters, undef;
		}
	}
	if($filter_count > 0){
		# TODO: strange: first occurance of the pattern that the lst size affects
		# the presence/absence of data after the list.
		my $request_from_buffers = read_bool($fh);
		$entity->{request_from_buffers} = JSON::true if $request_from_buffers;
	}

	# TODO: export compresses the filter list
	$entity->{request_filters} = \@request_filters if @request_filters;

	read_unknown($fh, 0x00, 0x00);
	 
	# circuit connection
	my $has_connections = read_bool($fh);
	if($has_connections){
		ep_circuit_connections($fh, $entity, $library);
		read_unknown($fh, 0x00);
	}
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_entity_infinity_container_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	# entity ids
	ep_entity_ids($fh, $entity, $library);

	# restriction aka. "bar"
	ep_bar($fh, $entity, $library);

	read_unknown($fh, 0x00, 0x00, 0x00);

	# circuit connection
	my $has_connections = read_bool($fh);
	if($has_connections){
		ep_circuit_connections($fh, $entity, $library);
		read_unknown($fh, 0x00);
	}
		
	# infinity_settings
	my @filters;
	my $filter_count = read_count8($fh);
	for(my $f=0; $f<$filter_count; ++$f){
		my $item_id = read_u16($fh);
		my $count = read_u32($fh);
		my $mode = read_u8($fh);
		push @filters, {
			name => get_name($library, Index::ITEM, $item_id),
			count => $count,
			mode => ("at-least", "at-most", "exactly")[$mode]
		};
	}
	$entity->{infinity_settings}{filters} = \@filters if @filters;
	my $remove_unfiltered_items = read_bool($fh);
	$entity->{infinity_settings}{remove_unfiltered_items} = (JSON::false, JSON::true)[$remove_unfiltered_items];

	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_entity_pipe_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_entity_pipe_to_ground_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	read_unknown($fh);
	ep_direction($$fh, $entity, $library);
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_entity_transport_belt_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	ep_entity_ids($fh, $entity, $library);
	ep_direction($$fh, $entity, $library);

	# circuit network connections
	my $has_circuit_connections = read_bool($fh);
	if($has_circuit_connections){
	
		# connections
		ep_circuit_connections($fh, $entity, $library);
		
		# circuit condition & logistic condition
		ep_conditions($fh, $entity, $library);
		read_unknown($fh, 0x00, 0x00);

		# mode of operation (specific for transport-belt)
		# maybe helpfull: https://lua-api.factorio.com/latest/defines.html#defines.control_behavior
		my $circuit_enable_disable = read_bool($fh);
		$entity->{control_behavior}{circuit_enable_disable} = json_bool($circuit_enable_disable);
		
		my $circuit_read_hand_contents = read_bool($fh);
		$entity->{control_behavior}{circuit_read_hand_contents} = json_bool($circuit_read_hand_contents);
		
		my $circuit_contents_read_mode = read_u8($fh);
		$entity->{control_behavior}{circuit_contents_read_mode} = $circuit_contents_read_mode;

		# really strange stuff
		read_unknown($fh, 0xff, 0xff, 0xff, 0xff);
		read_unknown($fh, 0xff, 0xff, 0xff, 0xff);
	}

	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_entity_underground_belt_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	read_unknown($fh);
	ep_direction($$fh, $entity, $library);
	my $is_output = read_bool($fh);
	if($is_output){
		$entity->{type} = "output";
	}
	else {
		$entity->{type} = "input";
	}
	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_entity_splitter_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	read_unknown($fh);
	ep_direction($$fh, $entity, $library);

	my $priorities = read_u8($fh);

	# "explanation": masks
	# => 0x10	-> output prio enabled
	# => 0x20	-> input priority enabled
	# => 0x0c	-> input priority left
	# => 0x03	-> output priority left
	# strange thing: why two bits for both 0x0c and 0x03?

	my %priority_mapping = (
		0x00 => [undef, undef],
		0x10 => [undef, "right"],
		0x13 => [undef, "left"],
		0x20 => ["right", undef],
		0x2c => ["left", undef],
		0x30 => ["right", "right"],
		0x33 => ["right", "left"],
		0x3c => ["left", "right"],
		0x3f => ["left", "left"]
	);
	my $mapped_priority = $priority_mapping{$priorities};;
	croak sprintf "unexpected splitter priority code 0x%02x", $priorities unless $mapped_priority;
	my ($input_priority, $output_priority) = @$mapped_priority;

	$entity->{input_priority} = $input_priority if $input_priority;
	$entity->{output_priority} = $output_priority if $output_priority;
	
	my $filter_id = read_u16($fh);
	if($filter_id){
		my $filter_name = get_name($library, Index::ITEM, $filter_id);
		$entity->{filter} = $filter_name;
	}
	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_electric_pole_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	ep_entity_ids($fh, $entity, $library);
	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00);
	
	# circuit network connections
	my $has_circuit_connections = read_bool($fh);
	if($has_circuit_connections){
		# connections
		ep_circuit_connections($fh, $entity, $library);
	}
	
	read_unknown($fh, 0x00);
	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_mining_drill_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	ep_entity_ids($fh, $entity, $library);
	ep_direction($$fh, $entity, $library);

	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);

	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);

	my $is_pumpjack = read_bool($fh); 	# 1 for pumpjack, 0 otherwise
	
	read_unknown($fh, 0x00);

	# circuit network connections
	my $has_circuit_connections = read_bool($fh);
	if($has_circuit_connections){
		# connections
		ep_circuit_connections($fh, $entity, $library);
		
		# circuit condition & logistic condition
		ep_conditions($fh, $entity, $library);
		read_unknown($fh, 0x00, 0x00);

		# mode of operation (specific for mining_drill)
		
		# maybe helpfull: https://lua-api.factorio.com/latest/defines.html#defines.control_behavior

		my $circuit_enable_disable = read_u8($fh);
		$entity->{control_behavior}{circuit_enable_disable} = json_bool($circuit_enable_disable);
		
		my $circuit_read_resources = read_u8($fh);
		$entity->{control_behavior}{circuit_read_resources} = json_bool($circuit_read_resources);

		read_unknown($fh, 0x00);
		
		my $circuit_resource_read_mode = read_u8($fh);;
		$entity->{control_behavior}{circuit_resource_read_mode} = $circuit_resource_read_mode;

		read_unknown($fh);
	}

	ep_modules($fh, $entity, $library);
	
	# TODO: Big surprise: Only one trailing zero-byte instead of 5!
	read_unknown($fh, 0x00);
}

sub read_offshore_pump_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;
	
	ep_entity_ids($fh, $entity, $library);
	ep_direction($fh, $entity, $library);

	read_unknown($fh, 0x00, 0x00, 0x00, 0x00);
	
	# circuit network connections
	my $has_circuit_connections = read_bool($fh);
	if($has_circuit_connections){
		# connections
		ep_circuit_connections($fh, $entity, $library);
		
		# circuit condition & logistic condition
		ep_conditions($fh, $entity, $library);
		read_unknown($fh, 0x00, 0x00);
	}
	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_assembling_machine_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	read_unknown($fh);
	my $recipe_id = read_u16($fh);
	if($recipe_id){
		my $recipe_name = get_name($library, Index::RECIPE, $recipe_id);
		$entity->{recipe} = $recipe_name;
	}

	ep_direction($fh, $entity, $library);

	ep_modules($fh, $entity, $library);
	
	# TODO: Big surprise: Only one trailing zero-byte instead of 5!
	read_unknown($fh, 0x00);
}

sub read_furnace_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
	ep_modules($fh, $entity, $library);
	# TODO: Big surprise: Only one trailing zero-byte instead of 5!
	read_unknown($fh);
}

sub read_storage_tank_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	ep_entity_ids($fh, $entity, $library);
	ep_direction($fh, $entity, $library);
	
	# circuit network connections
	my $has_circuit_connections = read_bool($fh);
	if($has_circuit_connections){
		# connections
		ep_circuit_connections($fh, $entity, $library);
	}
	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_pump_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	ep_entity_ids($fh, $entity, $library);
	ep_direction($fh, $entity, $library);

	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00);
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00);
	read_unknown($fh, 0x01, 0x00, 0x00, 0x00, 0x01);
	
	my $has_circuit_connections = read_bool($fh);
	if($has_circuit_connections){
		# connections
		ep_circuit_connections($fh, $entity, $library);
		
		# circuit condition & logistic condition
		ep_conditions($fh, $entity, $library);
		read_unknown($fh, 0x00, 0x00);
	}
	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

sub read_X_details(*$$){
	my $fh = shift;
	my $entity = shift;
	my $library = shift;

	# ...
	# dump_trailing_data($fh);
	
	read_unknown($fh, 0x00, 0x00, 0x00, 0x00, 0x00);
}

my %entity_details_handlers = (
	"inserter" => \&read_entity_inserter_details,
	"constant-combinator" => \&read_entity_constant_combinator_details,
	"container" => \&read_entity_container_details,
	"logistic-container" => \&read_entity_logistic_container_details,
	"infinity-container" => \&read_entity_infinity_container_details,
	"pipe" => \&read_entity_pipe_details,
	"pipe-to-ground" => \&read_entity_pipe_to_ground_details,
	"transport-belt" => \&read_entity_transport_belt_details,
	"underground-belt" => \&read_entity_underground_belt_details,
	"splitter" => \&read_entity_splitter_details,
	"electric-pole" => \& read_electric_pole_details,
	"mining-drill" => \&read_mining_drill_details,
	"offshore-pump" => \&read_offshore_pump_details,
	"assembling-machine" => \&read_assembling_machine_details,
	"furnace" => \&read_furnace_details,
	"storage-tank" => \&read_storage_tank_details,
	"pump" => \&read_pump_details,
);

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
	my $entry = get_entry($library, Index::ENTITY, $type_id);
	my $type_name = $entry->{name};
	my $type_class = $entry->{class};
	
	# position
	my ($delta_x, $delta_y) = read_delta_position($fh);
	my ($x, $y) = ($last_x + $delta_x, $last_y + $delta_y);

	printf "    [%d] \@%04x - x: %g, y: %g, '%s/%s'\n", $entity_index, $file_offset, $x, $y, $type_class, $type_name;
	my $entity = {
		name => $type_name,
		position => {
			x => $x,
			y => $y
		}
	};
	
	read_unknown($fh, 0x20);

	my $handler = $entity_details_handlers{$type_class};
	if($handler){
		$handler->($fh, $entity, $library);
	}
	else {
		croak "unexpected type-class '$type_class'";
	}
	
	return $entity;
}

################################################################
#
# parts for blueprints, blueprint books and blueprint library
#

# maybe helpfull: https://wiki.factorio.com/Version_string_format
sub bp_version(*$$){
	my $fh = shift;
	my $library = shift;
	my $result = shift;
	
	my @version;
	for(1..4){
		push @version, read_u16($fh);
	}
	printf "version: %s\n", join ".", @version;
	$result->{version} = \@version;
}

sub bp_migrations(*$$){
	my $fh = shift;
	my $library = shift;
	my $result = shift;

	my @migrations;
	my $count = read_count8($fh);
	printf "migrations: %d\n", $count;
	for(my $i=0; $i<$count; ++$i){
		my $mod_name = read_string($fh);
		my $migration_file = read_string($fh);
		printf "    [%d] mod '%s', migration '%s'\n", $i, $mod_name, $migration_file;
		push @migrations, { mod_name => $mod_name, migration_file => $migration_file }
	}
	
	$result->{migrations} = \@migrations;
}

sub bp_prototype_index(*){
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

sub bp_entities(*$$){
	my $fh = shift;
	my $library = shift;
	my $result = shift;
	
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
}

sub bp_tiles(*$$){
	my $fh = shift;
	my $library = shift;
	my $result = shift;
	
	my $tile_count = read_count32($fh);
	printf "tiles: %d\n", $tile_count;
	for(my $t=0; $t<$tile_count; ++$t){
		my $x = read_s32($fh);
		my $y = read_s32($fh);
		my $id = read_u8($fh);
		my $name = get_name($library, Index::TILE, $id);
		push @{$result->{tiles}}, {
			name => $name,
			position => {
				x => $x,
				y => $y
			}
		};
	}
}

sub bp_icons(*$$){
	my $fh = shift;
	my $library = shift;
	my $result = shift;

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
}

my %library_entry_handlers = (
	"blueprint" => \&read_blueprint,
	"blueprint-book" => \&read_blueprint_book,
	"deconstruction-item" => \&read_deconstruction_item,
	"upgrade-item" => \&read_upgrade_item,
);

sub bp_blueprints(*$$){
	my $fh = shift;
	my $library = shift;
	my $result = shift;
	
	my $blueprint_count = read_count32($fh);
	printf "\nblueprints: %d\n", $blueprint_count;
	my @blueprints;
	for(my $b=0; $b<$blueprint_count; ++$b){
		my $is_used = read_bool($fh);
		if($is_used){
			printf "\n[%d] library slot: used\n", $b;
			read_ignore($fh, 5); 	# perhaps some generation counter?
			my $type_id = read_u16($fh);
			my $type_entry = get_entry($library, Index::ITEM, $type_id);
			my $type_class = $type_entry->{class};
			my $type_handler = $library_entry_handlers{$type_class};
			croak sprintf "unexpected type-class: %04x '%s'", $type_id, $type_class unless $type_handler;
			my $handler_result = $type_handler->($fh, $library);
			push @blueprints, $handler_result;
		}
		else {
			printf "\n[%d] library slot: free\n", $b;
			push @blueprints, undef;
		}
	}
	$result->{blueprints} = \@blueprints;
}

################################################################
#
# blueprints, blueprint books, blueprint library and similar
#

sub read_upgrade_item(*$){
	my $fh = shift;
	my $library = shift;
	my $result = {};


	$result->{item} = "upgrade-planner";
	$result->{label} = read_string($fh);
	$result->{settings}{description} = read_string($fh);
	
	printf "upgrade-item '%s'\n", $result->{label};

	read_unknown($fh);

	bp_icons($fh, $library, $result);

	read_unknown($fh);


	my $reader = sub {
		my $is_item = read_bool($fh);
		my $id = read_u16($fh);
		
		return undef unless $id;
		if($is_item){
			return {
				type => "item",
				name => get_name($library, Index::ITEM, $id)
			};
		}
		else {
			return {
				type => "entity",
				name => get_name($library, Index::ENTITY, $id)
			};
		}
	};

	my $mapper_count = read_u8($fh);
	my @mappers;
	for(my $m=0; $m<$mapper_count; ++$m){
		# see read_type_and_name but the types are different :-(
		my $from = $reader->();
		my $to =$reader->();
		if( $from || $to ){
			push @mappers, {
				from => $from,
				to => $to
			};
		}
		else {
			push @mappers, undef;
		}
	}
	$result->{settings}{mappers} = \@mappers;

	return $result;	
}

sub read_deconstruction_item(*$){
	my $fh = shift;
	my $library = shift;
	my $result = {};

	$result->{item} = "deconstruction-planner";
	$result->{label} = read_string($fh);
	$result->{settings}{description} = read_string($fh);

	printf "deconstruction-item '%s'\n", $result->{label};

	read_unknown($fh);
	
	bp_icons($fh, $library, $result);

	my $entity_filter_mode = read_u8($fh);
	$result->{settings}{entity_filter_mode} = $entity_filter_mode if $entity_filter_mode;

	read_unknown($fh, 0x00);
	
	my $entity_filter_count = read_count8($fh);
	printf "entity-filters: %d\n", $entity_filter_count;
	my @entity_filters;
	for(my $f=0; $f<$entity_filter_count; ++$f){
		my $item_id = read_u16($fh);
		if($item_id != 0x00){
			my $item_name = get_name($library, Index::ENTITY, $item_id);
			push @entity_filters, $item_name;
		}
		else {
			push @entity_filters, undef;
		}
	}
	$result->{settings}{entity_filters} = \@entity_filters;

	my $trees_and_rocks_only = read_bool($fh);
	$result->{settings}{trees_and_rocks_only} = JSON::true if $trees_and_rocks_only;

	my $tile_filter_mode = read_u8($fh);
	$result->{settings}{tile_filter_mode} = $tile_filter_mode if $tile_filter_mode;

	my $tile_selection_mode = read_u8($fh);
	$result->{settings}{tile_selection_mode} = $tile_selection_mode if $tile_selection_mode;
	
	read_unknown($fh);

	my $tile_filter_count = read_count8($fh);
	printf "tile-filters: %d\n", $tile_filter_count;
	my @tile_filters;
	for(my $t=0; $t<$tile_filter_count; ++$t){
		my $tile_id = read_u8($fh);
		if($tile_id != 0x00){
			my $tile_name = get_name($library, Index::TILE, $tile_id);
			push @tile_filters, $tile_name;
		}
		else {
			push @tile_filters, undef;
		}
	}
	$result->{settings}{tile_filters} = \@tile_filters;
	
	return $result;
}

sub read_blueprint(*$){
	my $fh = shift;
	my $library = shift;
	my $result = {};

	my $file_position = tell($fh);
	
	$result->{item} = "blueprint";
	$result->{label} = read_string($fh);
	printf "blueprint '%s' (@%04x)\n", $result->{label}, $file_position;

	read_unknown($fh, 0x00, 0x00, 0xff);
	read_ignore($fh, 4); 	# maybe some offset (with previous 0xff an flexible u8/u32 length?)

	bp_version($fh, $library, $result);
	
	read_unknown($fh);

	bp_migrations($fh, $library, $result);

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

	bp_entities($fh, $library, $result);

	read_unknown($fh);

	bp_tiles($fh, $library, $result);

	read_unknown($fh);

	bp_icons($fh, $library, $result);

	return $result;
}

sub read_blueprint_book(*$){
	my $fh = shift;
	my $library = shift;
	my $result = {};

	my $file_position = tell $fh;
	
	$result->{item} = "blueprint-book";
	$result->{label} = read_string($fh);
	
	printf "blueprint-book '%s' (@%04x)\n", $result->{label}, $file_position;
	
	$result->{description} = read_string($fh);
	read_unknown($fh);
	bp_icons($fh, $library, $result);

	bp_blueprints($fh, $library, $result);

	my $active_index = read_u8($fh); 	# TODO: 8/32 length?
	$result->{active_index} = $active_index if $active_index;
	
	read_unknown($fh, 0x00);

	printf "end of book '%s' (@%04x)\n", $result->{label}, tell $fh;
	return $result;
}

sub read_blueprint_library(*){
	my $fh = shift;
	my $result = {};

	bp_version($fh, $result, $result);
	read_unknown($fh);
	bp_migrations($fh, $result, $result);
	$result->{prototypes} = bp_prototype_index($fh);

	read_unknown($fh, 0x00, 0x00);
	
	# Adding a blueprint and saving increments the counter, deleting and saving does not.
	my $counter = read_u32($fh);
	printf "counter: %d\n", $counter;
	$result->{_counter_} = $counter;

	# unix timestamp
	my $timestamp = read_u32($fh); 	# u32/s32?
	my $timestring = strftime "%FT%T%z", localtime $timestamp;  # localtime/gmtime?
	printf "timestamp: %s\n", $timestring;
	$result->{_save_timestamp_} = $timestring;

	read_unknown($fh, 0x01);

	bp_blueprints($fh, $result, $result);
	
	return $result;
}

################################################################
#
# utilities

# TODO: move to index XOR inline?
sub get_entry($$$){
	my $library = shift or croak;
	my $kind = shift or croak;
	my $id = shift or croak;
	
	my $result = $library->{prototypes}->entry($kind, $id);
	croak sprintf "##### unknown thing: kind: %s, id: %04x", $kind, $id unless $result;
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

sub json_bool($){
	my $arg = shift;
	return undef unless defined $arg;
	return JSON::true if $arg;
	return JSON::false;
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
