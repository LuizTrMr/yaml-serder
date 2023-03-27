package yaml_serder

import "core:fmt"
import "core:os"
import "core:reflect"
import "core:runtime"
import "core:strings"
import "core:mem"
import "core:strconv"

SerializeError :: enum {
	None,
	Unsupported_Type,
	Unsupported_Map_Key_Type,
}

serialize_yaml :: proc(value: any, options : SerializerOptions = {}) -> ([]byte, SerializeError) {
	opts: SerializerOptions
	if options == {} { // Default values
		opts = SerializerOptions{
			ident_size = 2,
			null_str   = true,
		}
	} else {
		opts = options
	}
	sb := strings.builder_make()
	err := ser_yaml(&sb, value, opts)
	return sb.buf[:], err
}

ser_yaml :: proc(sb: ^strings.Builder, v: any, opts: SerializerOptions, identation: int = 0) -> SerializeError {
	if v == nil {
		strings.write_string(sb, " null\n" if opts.null_str else " ~\n")
		return .None
	}

	id := v.id
	ti := reflect.type_info_base( type_info_of(id) )
	#partial switch info in ti.variant {
		// All unsupported types
		case reflect.Type_Info_Quaternion, reflect.Type_Info_Complex,
			 reflect.Type_Info_Matrix, reflect.Type_Info_Relative_Pointer,
			 reflect.Type_Info_Simd_Vector, reflect.Type_Info_Tuple,
			 reflect.Type_Info_Procedure, reflect.Type_Info_Soa_Pointer,
			 reflect.Type_Info_Multi_Pointer, reflect.Type_Info_Pointer,
			 reflect.Type_Info_Type_Id, reflect.Type_Info_Any,
			 reflect.Type_Info_Bit_Set, reflect.Type_Info_Union,
			 reflect.Type_Info_Named: {
				return .Unsupported_Type
		}

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

		case reflect.Type_Info_Enum: {
			ser_yaml(sb, any{v.data, info.base.id}, opts, identation+opts.ident_size) or_return
		}

		case reflect.Type_Info_Array: {
			if info.count == 0 {
				ser_yaml(sb, nil, opts, identation) or_return
			}
			for i in 0..<info.count {
				write_byte(sb, '-', identation)
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
				write_byte(sb, '-', identation)
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
				write_byte(sb, '-', identation)
				data := uintptr(array.data) + uintptr(i*info.elem_size)
				if is_record_type(info.elem.id) {
					strings.write_byte(sb, '\n')
					ser_yaml(sb, any{rawptr(data), info.elem.id}, opts, identation+1) or_return
				} else {
					ser_yaml(sb, any{rawptr(data), info.elem.id}, opts, identation) or_return
				}
			}
		}

		case reflect.Type_Info_Enumerated_Array: {
			// Serializes to int value: value, e.g.:
			// E :: enum { A = 1, B = 2 }
			// enum_arr := [E]int{ A = 2, B = 3 }
			// Serializes to: 1: 2; 2: 3
			index := runtime.type_info_base(info.index).variant.(reflect.Type_Info_Enum)
			element_id := info.elem.id
			if !info.is_sparse {
				if info.count == 0 {
					ser_yaml(sb, nil, opts, identation) or_return
				}
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
				if count == 0 {
					ser_yaml(sb, nil, opts, identation) or_return
				}
				sum   := 0
				for i in 0..<count {
					key := index.values[i]
					if i != 0 {
						sum += cast(int)index.values[i] - cast(int)index.values[i-1]
					}
					data := uintptr(v.data) + uintptr(sum*info.elem_size)
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
			}
		}

		case reflect.Type_Info_Map: {
			m := (^mem.Raw_Map)(v.data)
			if m != nil {
				if info.map_info == nil {
					return .Unsupported_Type
				}
				map_cap := uintptr(runtime.map_cap(m^))
				ks, vs, hs, _, _ := runtime.map_kvh_data_dynamic(m^, info.map_info)
				for bucket_index in 0..<map_cap {
					if !runtime.map_hash_is_valid(hs[bucket_index]) {
						continue
					}
					key   := rawptr(runtime.map_cell_index_dynamic(ks, info.map_info.ks, bucket_index))
					value := rawptr(runtime.map_cell_index_dynamic(vs, info.map_info.vs, bucket_index))

					// check for string type
					{
						v := any{key, info.key.id}
						ti := runtime.type_info_base(type_info_of(v.id))
						a := any{v.data, ti.id}
						name: string

						#partial switch info in ti.variant {
							case reflect.Type_Info_String: {
								switch s in a {
									case string: name = s
									case cstring: name = string(s)
								}
								write_key(sb, name, identation)
							}
							case: return .Unsupported_Map_Key_Type
						}
					}
					ser_yaml(sb, any{value, info.value.id}, opts, identation+opts.ident_size) or_return
				}
			} else {
				ser_yaml(sb, nil, opts, identation) or_return
			}
		}
		case: fmt.sbprintf(sb, " %v\n", v)
	}
	return .None
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

write_byte :: proc(sb: ^strings.Builder, b: byte, identation: int = 0) {
	whitespaces := make([]byte, identation)
	defer delete(whitespaces)
	for i in 0..<identation {
		whitespaces[i] = ' '
	}
	strings.write_bytes(sb, whitespaces)
	strings.write_byte(sb, b)
}

SerializerOptions :: struct {
	ident_size: int,
	null_str: bool,
}

is_empty :: proc(v: any) -> bool {
	id := v.id
	ti := reflect.type_info_base( type_info_of(id) )
	#partial switch info in ti.variant {
		case reflect.Type_Info_Array:{
			if info.count == 0 { return true }
		}
		case reflect.Type_Info_Slice: {
			slice := cast(^mem.Raw_Slice)v.data
			if slice.len == 0 { return true }
		}
		case reflect.Type_Info_Dynamic_Array: {
			array := cast(^mem.Raw_Dynamic_Array)v.data
			if array.len == 0 { return true }
		}
		case reflect.Type_Info_Enumerated_Array: {
			fmt.println("Enumerated_Array")
			if !info.is_sparse {
				fmt.println("info.count =", info.count)
				if info.count == 0 { return true }
			} else {
				index := runtime.type_info_base(info.index).variant.(reflect.Type_Info_Enum)
				count := len(index.values)
				fmt.println("count =", count)
				if count == 0 { return true }
			}
		}
		case: return false
	}
	return false
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
