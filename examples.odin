package yaml_serder

import "core:fmt"

Weapon :: enum {
	Sword,
	Axe,
	Bow,
}

Point :: struct {
	x: int, y: int,
}

Entity :: struct {
	p: Point,
	dx: f32, dy: f32,
	name: string,
	weapons: []Weapon,
}

main :: proc() {
	entt := Entity{
		Point{5, 10},
		19.1,
		20.2,
		"Hero",
		[]Weapon{.Sword, .Bow},
	}
	data, err := serialize_yaml(entt)
	switch err {
		case .None: {
			fmt.print(string(data))
		}
		case .Unsupported_Type: {
			fmt.println("err :", err)
		}
		case .Unsupported_Map_Key_Type: {
			fmt.println("err :", err)
		}
	}
}
