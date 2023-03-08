// Just check if identation is != 0 to write the new line
package main

import "core:fmt"
import "core:os"
import "core:reflect"
import "core:runtime"
import "core:strings"
import "core:mem"
import "core:strconv"

SerializeError :: enum {
	Unsupported_Type,
}

B :: struct {
	anything: int,
	boolean: bool,
}

A :: struct {
	i: i32,
	b_struct: B,
}

Test :: struct {
	arr: [2][2]int,
	d_arr: [dynamic]int,
	s: A,
}

SomeEnum :: enum {
	A = 2,
	B = 4,
	C = 10,
	D = 18,
}

main :: proc() {
	file, err := os.open("serde/out.yaml")
	if err != os.ERROR_NONE {
		fmt.println("ERROR while opening file: ", err)
	}
	defer os.close(file)

	// Tests
	dyn := [dynamic]int{1,2}
	append(&dyn, 3)
	enumerated_arr := #sparse[SomeEnum]A{
		.A = A{14, B{0, false}},
		.B = A{20, B{1, true}},
		.C = A{35, B{2, false}},
		.D = A{49, B{3, true}},
	}
	test := Test{
		[2][2]int{
			[2]int{1, 2},
			[2]int{3, 4},
		},
		nil,
		A{10, B{0, true}},
	}
	data, ser_err := serialize_yaml(test, SerializerOptions{false, 2, true})
	if ser_err != nil {
		fmt.println("ERROR while serializing: ", err)
	} else {
		os.write(file, data)
	}
}

serialize_yaml :: proc(value: any, options : SerializerOptions = {}) -> ([]byte, SerializeError) {
	opts: SerializerOptions
	if options == {} {
		opts = SerializerOptions{true, 2, true}
	} else { opts = options }
	sb := strings.builder_make()
	err := ser_yaml(&sb, value, opts)
	return sb.buf[:], err
}

ser_yaml :: proc(sb: ^strings.Builder, v: any, opts: SerializerOptions, identation: int = 0) -> SerializeError {
	if v == nil {
		strings.write_string(sb, " null\n" if opts.null_str else " ~\n")
		return nil
	}
	id := v.id
	ti := reflect.type_info_base( type_info_of(id) )

	#partial switch info in ti.variant {
		case reflect.Type_Info_Struct: {
			fields := reflect.struct_fields_zipped(id)
			for field in fields {
				field_value := reflect.struct_field_value_by_name(v, field.name)
				write_key(sb, field.name, identation)
				if is_empty( field_value ) {
					strings.write_string(sb, " null\n" if opts.null_str else " ~\n")
					continue
				}
				if is_record_type(field_value.id) {
					strings.write_byte(sb, '\n')
				}
				ser_yaml(sb, field_value, opts, identation+opts.ident_size) or_return
			}
		}

		case reflect.Type_Info_Array: {
			if info.count == 0 {
				ser_yaml(sb, nil, opts, identation) or_return
			}
			for i in 0..<info.count {
				write_bytes(sb, []byte{'-'}, identation)
				data := uintptr(v.data) + uintptr(i*info.elem_size)
				if is_record_type(info.elem.id) {
					strings.write_byte(sb, '\n')
					ser_yaml(sb, any{rawptr(data), info.elem.id}, opts, identation+1) or_return
				} else {
					ser_yaml(sb, any{rawptr(data), info.elem.id}, opts, identation) or_return
				}
			}
		}

		case reflect.Type_Info_Slice: {
			slice := cast(^mem.Raw_Slice)v.data
			if slice.len == 0 {
				ser_yaml(sb, nil, opts, identation) or_return
			}
			for i in 0..<slice.len {
				write_bytes(sb, []byte{'-'}, identation)
				data := uintptr(slice.data) + uintptr(i*info.elem_size)
				if is_record_type(info.elem.id) {
					strings.write_byte(sb, '\n')
					ser_yaml(sb, any{rawptr(data), info.elem.id}, opts, identation+1) or_return
				} else {
					ser_yaml(sb, any{rawptr(data), info.elem.id}, opts, identation) or_return
				}
			}
		}

		case reflect.Type_Info_Dynamic_Array: {
			array := cast(^mem.Raw_Dynamic_Array)v.data
			if array.len == 0 {
				ser_yaml(sb, nil, opts, identation) or_return
			}
			for i in 0..<array.len {
				write_bytes(sb, []byte{'-'}, identation)
				data := uintptr(array.data) + uintptr(i*info.elem_size)
				if is_record_type(info.elem.id) {
					strings.write_byte(sb, '\n')
					ser_yaml(sb, any{rawptr(data), info.elem.id}, opts, identation+1) or_return
				} else {
					ser_yaml(sb, any{rawptr(data), info.elem.id}, opts, identation) or_return
				}
			}
		}

		case reflect.Type_Info_Enumerated_Array: { // TODO: if empty
			// Serializes to int value: value, e.g.:
			// E :: enum { A = 1, B = 2 }
			// enum_arr := [E]int{ A = 2, B = 3 }
			// Serializes to: 1: 2; 2: 3
			strings.write_byte(sb, '\n')
			index := runtime.type_info_base(info.index).variant.(runtime.Type_Info_Enum)
			element_id := info.elem.id
			if !info.is_sparse {
				for i in 0..<info.count {
					key  := index.values[i]
					data := uintptr(v.data) + uintptr(i*info.elem_size)
					// -- Convert Type_Info_Enum_Value to string: Taken from `strings.write_i64`
					buf: [32]byte
					s := strconv.append_bits(buf[:], u64(cast(i64)key), 10, true, 64, strconv.digits, nil)
					// --
					if is_record_type(element_id) {
						write_key(sb, s, identation)
						strings.write_byte(sb, '\n')
					} else {
						write_key(sb, s, identation)
					}
					ser_yaml(sb, any{rawptr(data), info.elem.id}, opts, identation+opts.ident_size) or_return
				}
			} else {
				count := len(index.values)
				sum   := 0
				for i in 0..<count {
					key := index.values[i]
					if i != 0 {
						sum += cast(int)index.values[i] - cast(int)index.values[i-1]
					}
					data := uintptr(v.data) + uintptr(sum*info.elem_size)
					// -- Convert Type_Info_Enum_Value to string:
					buf: [32]byte
					s := strconv.append_bits(buf[:], u64(cast(i64)key), 10, true, 64, strconv.digits, nil)
					// --
					if is_record_type(element_id) {
						write_key(sb, s, identation)
						strings.write_byte(sb, '\n')
					} else {
						write_key(sb, s, identation)
					}
					ser_yaml(sb, any{rawptr(data), info.elem.id}, opts, identation+opts.ident_size) or_return
				}
			}
		}

		case reflect.Type_Info_Map: { // TODO: Understand better
			m := (^mem.Raw_Map)(v.data)
			if m != nil {
				if info.map_info == nil {
					// TODO: return shit map info
					panic("something bad")
				}
				map_cap := uintptr(runtime.map_cap(m^))
				ks, vs, hs, _, _ := runtime.map_kvh_data_dynamic(m^, info.map_info)
				i := 0
				for bucket_index in 0..<map_cap {
					if !runtime.map_hash_is_valid(hs[bucket_index]) {
						continue
					}
					i += 1
					key   := rawptr(runtime.map_cell_index_dynamic(ks, info.map_info.ks, bucket_index))
					value := rawptr(runtime.map_cell_index_dynamic(vs, info.map_info.vs, bucket_index))

					// check for string type
					{
						v := any{key, info.key.id}
						ti := runtime.type_info_base(type_info_of(v.id))
						a := any{v.data, ti.id}
						name: string

						#partial switch info in ti.variant {
							case runtime.Type_Info_String: {
								switch s in a {
									case string: name = s
									case cstring: name = string(s)
								}
								write_key(sb, name, identation)
							}
							case: // TODO: return Shit type for key
						}
					}
					ser_yaml(sb, any{value, info.value.id}, opts, identation+opts.ident_size) or_return
				}
			}
		}
		case: fmt.sbprintf(sb, " %v\n", v)
	}
	return nil
}

write_key :: proc(sb: ^strings.Builder, key: string, identation: int) {
	byte_slice := make([]byte, identation)
	defer delete(byte_slice)
	for i in 0..<identation {
		byte_slice[i] = ' '
	}
	whitespaces := string(byte_slice)
	fmt.sbprintf(sb, "%v%v:", whitespaces, key)
}

write_bytes :: proc(sb: ^strings.Builder, bytes: []byte, identation: int = 0) {
	whitespaces := make([]byte, identation)
	defer delete(whitespaces)
	for i in 0..<identation {
		whitespaces[i] = ' '
	}
	strings.write_bytes(sb, whitespaces)
	strings.write_bytes(sb, bytes)
}

SerializerOptions :: struct {
	one_line_array: bool,
	ident_size: int,
	null_str: bool,
}

is_empty :: proc(v: any) -> bool {
	id := v.id
	ti := reflect.type_info_base( type_info_of(id) )
	#partial switch info in ti.variant {
		case reflect.Type_Info_Array: if info.count == 0 { return true }
		case reflect.Type_Info_Slice: {
			slice := cast(^mem.Raw_Slice)v.data
			if slice.len == 0 { return true }
		}
		case reflect.Type_Info_Dynamic_Array: {
			array := cast(^mem.Raw_Dynamic_Array)v.data
			if array.len == 0 { return true }
		}
		case reflect.Type_Info_Enumerated_Array: { // TODO: if empty
		}
		case: return false
	}
	return false
}


is_struct :: proc(id: typeid) -> bool { using reflect
	type := type_info_of(id)
	base_type := reflect.type_info_base(type).variant
	#partial switch in base_type {
		case Type_Info_Struct: return true
		case: return false
	}
}

is_record_type :: proc(id: typeid) -> bool { using reflect
	type := type_info_of(id)
	base_type := reflect.type_info_base(type).variant
	#partial switch in base_type {
		case Type_Info_Struct, Type_Info_Array,
			 Type_Info_Slice, Type_Info_Dynamic_Array,
			 Type_Info_Map, Type_Info_Enumerated_Array: return true
		case: return false
	}
}
