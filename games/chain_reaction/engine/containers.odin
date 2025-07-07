package engine

import "base:intrinsics"

import "core:mem"

Sparse_Array :: struct(
	$Key:      typeid,
	$Value:    typeid,
	$Capacity: uint,
) where intrinsics.type_is_valid_map_key(Key) {
	data:         [Capacity]Value,
	length:       uint,
	key_to_index: map[Key]uint,
	index_to_key: map[uint]Key,
	allocator:    mem.Allocator,
}

sparse_array_create :: proc(
	$Key:      typeid,
	$Value:    typeid,
	$Capacity: uint,
	allocator := context.allocator,
) -> (
	sparse_array: Sparse_Array(Key, Value, Capacity)
) {
	context.allocator = allocator

	sparse_array = {
		key_to_index = make(map[Key]uint),
		index_to_key = make(map[uint]Key),
		allocator    = allocator
	}

	return sparse_array
}

sparse_array_destroy :: proc(
	sparse_array: ^Sparse_Array($Key, $Value, $Capacity)
) {
	assert(sparse_array != nil)
	context.allocator = sparse_array.allocator

	delete(sparse_array.key_to_index)
	delete(sparse_array.index_to_key)
}

sparse_array_insert :: proc(
	sparse_array: ^Sparse_Array($Key, $Value, $Capacity),
	key:          Key,
) -> (
	value: ^Value
) {
	assert(sparse_array != nil)
	assert(sparse_array.length < Capacity)
	assert(key not_in sparse_array.key_to_index)
	context.allocator = sparse_array.allocator

	sparse_array.key_to_index[key] = sparse_array.length
	sparse_array.index_to_key[sparse_array.length] = key
	defer sparse_array.length += 1

	return &sparse_array.data[sparse_array.length]
}

sparse_array_remove :: proc(
	sparse_array: ^Sparse_Array($Key, $Value, $Capacity),
	key:          Key,
) {
	assert(sparse_array != nil)
	assert(sparse_array.length > 0)
	assert(key in sparse_array.key_to_index)
	context.allocator = sparse_array.allocator

	last_element := &sparse_array.data[sparse_array.length-1]
	
	removed_index := sparse_array.key_to_index[key]
	removed_element := &sparse_array.data[removed_index]
	
	removed_element^ = last_element^

	last_key := sparse_array.index_to_key[sparse_array.length-1]
	sparse_array.index_to_key[removed_index] = last_key
	sparse_array.key_to_index[last_key] = removed_index

	delete_key(&sparse_array.key_to_index, key)
	delete_key(&sparse_array.index_to_key, sparse_array.length-1)

	sparse_array.length -= 1
}

sparse_array_get :: proc(
	sparse_array: ^Sparse_Array($Key, $Value, $Capacity),
	key:          Key,
) -> (
	value: ^Value
) {	
	assert(sparse_array != nil)
	assert(key in sparse_array.key_to_index)

	return &sparse_array.data[sparse_array.key_to_index[key]]
}

sparse_array_length :: proc(
	sparse_array: ^Sparse_Array($Key, $Value, $Capacity),
) -> (
	length: uint
) {
	assert(sparse_array != nil)

	return sparse_array.length
}

sparse_array_contains :: proc(
	sparse_array: ^Sparse_Array($Key, $Value, $Capacity),
	key:          Key,
) -> (
	contains: bool
) {
	assert(sparse_array != nil)

	return key in sparse_array.key_to_index
}

sparse_array_slice :: proc{
	sparse_array_slice_range,
	sparse_array_slice_whole,
}

sparse_array_slice_range :: proc(
	sparse_array: ^Sparse_Array($Key, $Value, $Capacity),
	begin:        uint,
	end:          uint,
) -> (
	slice: []Value
) {
	assert(sparse_array != nil)
	assert(begin <= end)
	assert(end <= sparse_array.length)

	return sparse_array.data[begin:end]
}

sparse_array_slice_whole :: proc(
	sparse_array: ^Sparse_Array($Key, $Value, $Capacity),
) -> (
	slice: []Value
) {
	assert(sparse_array != nil)
	
	return sparse_array.data[:sparse_array.length]
}
