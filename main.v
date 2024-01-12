import gg
import gx
import math

const tile_size = 10

enum Variant as u8 {
	@none
	not
	wire
}

enum Orientation as u8 {
	north
	south
	east
	west
}

struct GlobalWire {
mut:
	state bool
	wires []i64
	inputs []i64
	outputs []i64
}

struct Wire {
mut:
	id_glob_wire i64
	destroyed bool
	in_gate bool
	x i64
	y i64
}

struct Not {
mut:
	output i64
	state bool
	orientation Orientation
	destroyed bool
	in_gate bool
	x i64
	y i64
}

interface Element {
mut:
	destroyed bool
	in_gate bool
	x i64
	y i64
}

@[heap]
struct Chunk {
mut:
	x i64
	y i64
	tiles [][]i64 = [][]i64{len:16, init:[]i64{len:16, init:-1}}
}

struct App {
mut:
    gg    &gg.Context = unsafe { nil }
	elements []Element
	destroyed []i64
	chunks []Chunk  // reopti les chunks pour éviter les cache misses en séparant les coords des 2D arrays
	wire_groups []GlobalWire
	queue []i64
	queue_gwires []i64

	mouse_x int
	mouse_y int

	nb_updates i64 = 1
	build_selected_type Variant
	build_orientation Orientation
}


fn main() {
    mut app := &App{}
    app.gg = gg.new_context(
        fullscreen: true
        create_window: true
        window_title: '- Nots -'
        user_data: app
        bg_color: gx.white
        frame_fn: on_frame
        event_fn: on_event
        sample_count: 6
    )
	app.build_selected_type = .wire
	app.build_orientation = .west
	app.place_in(0, 1) or {panic(err)}
	app.build_selected_type = .not
	for i in 1..98 {
		app.place_in(i, 1) or {panic(err)}
	}
	app.update()
	app.build_selected_type = .wire
	app.place_in(98, 1) or {panic(err)}
	app.update()
	for i in 0..99 {
		app.place_in(i, 2) or {panic(err)}
		app.update()
	}
	
    //lancement du programme/de la fenêtre
    app.gg.run()
}

fn (mut app App) update() {
	mut new_queue := []i64{}
	for updated in app.queue {
		mut elem := &app.elements[updated]
		match mut elem {
			Not {
				if elem.output >= 0 {
					mut output := &app.elements[elem.output]
					if !output.destroyed {
						match mut output {
							Not {
								output.state = !elem.state
								new_queue << elem.output
							}
							Wire {
								if elem.state {
									if updated !in app.wire_groups[output.id_glob_wire].inputs {
										if app.wire_groups[output.id_glob_wire].inputs.len == 0 {
											app.queue_gwires << output.id_glob_wire
										}
										app.wire_groups[output.id_glob_wire].inputs << updated
									}
								} else {
									mut is_in := false
									for i, input_id in app.wire_groups[output.id_glob_wire].inputs {
										if input_id == updated {
											app.wire_groups[output.id_glob_wire].inputs.delete(i)
											is_in = true
											break
										}
									}
									if app.wire_groups[output.id_glob_wire].inputs.len == 0 && is_in {
										app.queue_gwires << output.id_glob_wire
									}										
								}
							}
							else {}
						}
					}
				}
			}
			else {}
		}
	}
	mut new_queue_gwires := []i64{}
	for updated in app.queue_gwires {
		mut gwire := &app.wire_groups[updated]
		for output_id in gwire.outputs {
			mut output := &app.elements[output_id]
			if !output.destroyed {
				if mut output is Not{
					output.state = gwire.inputs.len == 0
					new_queue << output_id
				}
			} else {
				panic("elem detruit dans les outputs du wire")
			}
		}
	}
	app.queue = new_queue.clone()
	app.queue_gwires = new_queue_gwires.clone()
}

fn on_frame(mut app App) {
	for _ in 0..app.nb_updates {
		app.update()
	}

    //Draw
    app.gg.begin()
	for chunk in app.chunks {
		for line in chunk.tiles {
			for nb_element in line {
				if nb_element >= 0 {
					mut element := &app.elements[nb_element]
					match mut element {
						Not {
							color := if element.state {gx.green} else {gx.red}
							app.gg.draw_square_filled(f32(element.x*tile_size), f32(element.y*tile_size), tile_size, gx.black)
							rotation := match element.orientation {
								.north {
									-90
								}
								.south {
									90
								}
								.east {
									0
								}
								.west {
									180
								}
							}
							app.gg.draw_polygon_filled(f32(element.x*tile_size)+tile_size/2.0, f32(element.y*tile_size)+tile_size/2.0, tile_size/2.0, 3, rotation, color)
						}
						Wire {
							//seems like the id_glob_wire didn't get updated properly
							color := if app.wire_groups[element.id_glob_wire].inputs.len > 0 {gg.Color{255, 255, 0, 255}} else {gx.black}
							app.gg.draw_square_filled(f32(element.x*tile_size), f32(element.y*tile_size), tile_size, color)
						}
						else {}
					}
				}
			}
		}
	}
	app.gg.draw_square_filled(f32(app.mouse_x*tile_size), f32(app.mouse_y*tile_size), tile_size, gg.Color{100, 100, 100, 100})
	app.gg.show_fps()
    app.gg.end()
}

fn on_event(e &gg.Event, mut app App){
	app.mouse_x, app.mouse_y 
	= mouse_to_coords(e.mouse_x, e.mouse_y)
    match e.typ {
        .key_down {
            match e.key_code {
                .escape {app.gg.quit()}
				.up {app.build_orientation = .north}
				.down {app.build_orientation = .south}
				.left {app.build_orientation = .west}
				.right {app.build_orientation = .east}
				.enter {
					match app.build_selected_type {
						.not {app.build_selected_type = .wire}
						.wire {app.build_selected_type = .not}
						else {app.build_selected_type = .not}
					}
				}
                else {}
            }
        }
        .mouse_up {
            match e.mouse_button{
                .left{
					app.place_in(app.mouse_x, app.mouse_y) or {println(err)}
				}
				.right {
					
					app.delete_in(app.mouse_x, app.mouse_y) or {println(err)}
				}
                else{}
        }}
        else {}
    }
}

fn (mut app App) delete_in(x int, y int) ! {
	mut place_chunk := app.get_chunk_at_coords(x, y)
	old_id := place_chunk.tiles[math.abs(y-place_chunk.y*16)][math.abs(x-place_chunk.x*16)] 
	if old_id >= 0 {
		place_chunk.tiles[math.abs(y-place_chunk.y*16)][math.abs(x-place_chunk.x*16)] = -1
		app.elements[old_id].destroyed = true
		app.destroyed << old_id
		mut destroyed := &app.elements[old_id]
		match mut destroyed {
			Not {
				input := match destroyed.orientation {
					.north {
						chunk := app.get_chunk_at_coords(x, y+1)
						chunk.tiles[math.abs(y+1-chunk.y*16)][math.abs(x-chunk.x*16)]
					}
					.south {
						chunk := app.get_chunk_at_coords(x, y-1)
						chunk.tiles[math.abs(y-1-chunk.y*16)][math.abs(x-chunk.x*16)]
					}
					.east {
						chunk := app.get_chunk_at_coords(x-1, y)
						chunk.tiles[math.abs(y-chunk.y*16)][math.abs(x-1-chunk.x*16)]
					}
					.west {
						chunk := app.get_chunk_at_coords(x+1, y)
						chunk.tiles[math.abs(y-chunk.y*16)][math.abs(x+1-chunk.x*16)]
					}
				}
				if input != -1 {
					mut input_elem := &app.elements[input]
					match mut input_elem {
						Not {
							if input_elem.output == old_id {
								input_elem.output = -1
							}
						}
						Wire {
							i := app.wire_groups[input_elem.id_glob_wire].outputs.index(old_id)
							app.wire_groups[input_elem.id_glob_wire].outputs.delete(i)
						}
						else {}
					}
				}
				if destroyed.output > 0 {
					mut output_elem := &app.elements[destroyed.output]
					match mut output_elem {
						Wire {
							if destroyed.state {
								i := app.wire_groups[output_elem.id_glob_wire].inputs.index(old_id)
								app.wire_groups[output_elem.id_glob_wire].inputs.delete(i)
								if app.wire_groups[output_elem.id_glob_wire].inputs.len == 0 {
									app.wire_groups[output_elem.id_glob_wire].state = false
									app.queue_gwires << output_elem.id_glob_wire
								}
							}
						}
						Not {
							app.queue << old_id
						}
						else {}
					}
				}
				destroyed.state = false
			}
			Wire {
				mut to_process := []i64{}
				mut final_wires := []GlobalWire{}
				for pos in [[0, 1], [0, -1], [1, 0], [-1,0]] {
					chunk := app.get_chunk_at_coords(x+pos[0], y+pos[1])
					elem_id := chunk.tiles[math.abs(y+pos[1]-chunk.y*16)][math.abs(x+pos[0]-chunk.x*16)]
					if elem_id >= 0 {
						mut elem := &app.elements[elem_id]
						if !elem.destroyed {
							match mut elem {
								Wire {
									to_process << elem_id
								}
								Not {
									if elem.output == old_id {
										elem.output = -1
									}
								}
								else {}
							}
						}
					}
				}
				for element_id in to_process {
					mut current := &app.elements[element_id]
					if final_wires == [] {
						final_wires << GlobalWire{}
						final_wires[0].wires << element_id
						for pos in [[0, 1], [0, -1], [1, 0], [-1,0]] {
							chunk := app.get_chunk_at_coords(int(current.x+pos[0]), int(current.y+pos[1]))
							elem_id := chunk.tiles[math.abs(int(current.y)+pos[1]-chunk.y*16)][math.abs(int(current.x)+pos[0]-chunk.x*16)]
							if elem_id >= 0 {
								mut elem := &app.elements[elem_id]
								if !elem.destroyed {
									match mut elem {
										Wire {
											to_process << elem_id
										}
										Not {
											match pos {
												[0, 1] {
													match elem.orientation {
														.north { if elem.state {final_wires[0].inputs << elem_id} }
														.south { final_wires[0].outputs << elem_id }
														else {}
													}
												}
												[0, -1] {
													match elem.orientation {
														.south { if elem.state {final_wires[0].inputs << elem_id} }
														.north { final_wires[0].outputs << elem_id }
														else {}
													}
												}
												[1, 0] {
													match elem.orientation {
														.west { if elem.state {final_wires[0].inputs << elem_id} }
														.east { final_wires[0].outputs << elem_id }
														else {}
													}
												}
												[-1, 0] {
													match elem.orientation {
														.east { if elem.state {final_wires[0].inputs << elem_id} }
														.west { final_wires[0].outputs << elem_id }
														else {}
													}
												}
												else {}
											}
										}
										else {}
									}
								}
							}
						}
					} else {
						mut id_gwires := []i64{}
						mut inputs := []i64{}
						mut outputs := []i64{}
						for pos in [[0, 1], [0, -1], [1, 0], [-1, 0]] {
							chunk := app.get_chunk_at_coords(int(current.x)+pos[0], int(current.y)+pos[1])
							elem_id := chunk.tiles[math.abs(int(current.y)+pos[1]-chunk.y*16)][math.abs(int(current.x)+pos[0]-chunk.x*16)]

							if elem_id >= 0 {
								mut elem := &app.elements[elem_id]
								if !elem.destroyed {
									match mut elem {
										Wire {
											mut id_g_fil := -1
											for i, gfil in final_wires {
												if gfil.wires.index(elem_id) != -1 {
													id_g_fil = i
												}
											}
											if id_g_fil == -1 {
												if elem_id !in to_process {
													to_process << elem_id
												}
											} else {
												id_gwires << id_g_fil
											}											
										}
										Not {
											match pos {
												[0, 1] {
													match elem.orientation {
														.north { if elem.state {inputs << elem_id} }
														.south { outputs << elem_id }
														else {}
													}
												}
												[0, -1] {
													match elem.orientation {
														.south { if elem.state {inputs << elem_id} }
														.north { outputs << elem_id }
														else {}
													}
												}
												[1, 0] {
													match elem.orientation {
														.west { if elem.state {inputs << elem_id} }
														.east { outputs << elem_id }
														else {}
													}
												}
												[-1, 0] {
													match elem.orientation {
														.east { if elem.state {inputs << elem_id} }
														.west { outputs << elem_id }
														else {}
													}
												}
												else {}
											}
										}
										else {}
									}
								}
							}
						}
						mut tmp_map := map[i64]bool{}
						for k in id_gwires {
							tmp_map[k] = false
						}
						id_gwires = tmp_map.keys()
						id_gwires.sort()
						if id_gwires.len > 1 {
							assert id_gwires.len <= 4
							for id in id_gwires[1..] {
								final_wires[id_gwires[0]].wires << final_wires[id].wires
								final_wires[id_gwires[0]].inputs << final_wires[id].inputs
								final_wires[id_gwires[0]].outputs << final_wires[id].outputs
							}
							id_gwires = [id_gwires[0]]
							final_wires[id_gwires[0]].wires << element_id
							final_wires[id_gwires[0]].inputs << inputs
							final_wires[id_gwires[0]].outputs << outputs
						} else if id_gwires.len == 1 {
							final_wires[id_gwires[0]].wires << element_id
							final_wires[id_gwires[0]].inputs << inputs
							final_wires[id_gwires[0]].outputs << outputs
						} else if id_gwires.len == 0 {
							final_wires << GlobalWire{}
							final_wires[final_wires.len-1].wires << element_id
							final_wires[final_wires.len-1].inputs << inputs
							final_wires[final_wires.len-1].outputs << outputs
						}
					}
				}
				for i, mut fwire in final_wires {
					fwire.state = fwire.inputs.len > 0
					if !fwire.state && app.wire_groups[destroyed.id_glob_wire].state {
						for output_id in fwire.outputs {
							mut output := &app.elements[output_id]
							if mut output is Not {
								output.state = true
							}
							app.queue << output_id
						}
					}
					for wire_id in fwire.wires {
						mut wire := &app.elements[wire_id]
						if mut wire is Wire {
							wire.id_glob_wire = app.wire_groups.len - 1 + i
						}
					}
					// TODO update the estinguished outputs
				}
				app.wire_groups[destroyed.id_glob_wire] = final_wires[0]
				app.wire_groups << final_wires#[1..]
			}
			else {}
		}
	} else {
		return error("Not in a filled space")
	}
}

fn (mut app App) place_in(x int, y int) ! {
	match app.build_selected_type {
		.@none{}
		.not {
			mut id := i64(0)
			if app.destroyed.len == 0 {
				id = app.elements.len
			} else {
				id = app.destroyed[0]
				app.destroyed.delete(0)
				// remplacer l'element
			}
			mut place_chunk := app.get_chunk_at_coords(x, y)
			if place_chunk.tiles[math.abs(y-place_chunk.y*16)][math.abs(x-place_chunk.x*16)] < 0 {
				place_chunk.tiles[math.abs(y-place_chunk.y*16)][math.abs(x-place_chunk.x*16)] = id
			} else {
				return error("Not in an empty space")
			}
			
			mut output := match app.build_orientation {
				.north {
					chunk := app.get_chunk_at_coords(x, y-1)
					chunk.tiles[math.abs(y-1-chunk.y*16)][math.abs(x-chunk.x*16)]
				}
				.south {
					chunk := app.get_chunk_at_coords(x, y+1)
					chunk.tiles[math.abs(y+1-chunk.y*16)][math.abs(x-chunk.x*16)]
				}
				.east {
					chunk := app.get_chunk_at_coords(x+1, y)
					chunk.tiles[math.abs(y-chunk.y*16)][math.abs(x+1-chunk.x*16)]
				}
				.west {
					chunk := app.get_chunk_at_coords(x-1, y)
					chunk.tiles[math.abs(y-chunk.y*16)][math.abs(x-1-chunk.x*16)]
				}
			}
			if output != -1 {
				if app.elements[output].destroyed {
					output = -1
				} else {
					mut output_elem := &app.elements[output]
					match mut output_elem {
						Not {
							if output_elem.orientation != app.build_orientation {
								output = -1
							}
						}
						else {}
					}
				}
			}
			
			input := match app.build_orientation {
				.north {
					chunk := app.get_chunk_at_coords(x, y+1)
					chunk.tiles[math.abs(y+1-chunk.y*16)][math.abs(x-chunk.x*16)]
				}
				.south {
					chunk := app.get_chunk_at_coords(x, y-1)
					chunk.tiles[math.abs(y-1-chunk.y*16)][math.abs(x-chunk.x*16)]
				}
				.east {
					chunk := app.get_chunk_at_coords(x-1, y)
					chunk.tiles[math.abs(y-chunk.y*16)][math.abs(x-1-chunk.x*16)]
				}
				.west {
					chunk := app.get_chunk_at_coords(x+1, y)
					chunk.tiles[math.abs(y-chunk.y*16)][math.abs(x+1-chunk.x*16)]
				}
			}
			mut state := true // because a not gate without input is a not gate with off input
			if input >= 0 {
				mut elem_input := &app.elements[input]
				match mut elem_input {
					Not {
						if elem_input.orientation == app.build_orientation {
							elem_input.output = id
							state = !elem_input.state
						}
					}
					Wire {
						state = !app.wire_groups[elem_input.id_glob_wire].state
						app.wire_groups[elem_input.id_glob_wire].outputs << id
					}
					else {}
				}
			}
			if id == app.elements.len {
				app.elements <<	Not {
					output: output
					state: state
					orientation: app.build_orientation
					destroyed: false
					in_gate: false
					x: x
					y: y
				}
			} else {
				app.elements[id] = Not {
					output: output
					state: state
					orientation: app.build_orientation
					destroyed: false
					in_gate: false
					x: x
					y: y
				}
			}
			
			if output >= 0 {
				app.queue << id
			}
		}
		.wire {
			mut id := i64(0)
			if app.destroyed.len == 0 {
				id = app.elements.len
			} else {
				id = app.destroyed[0]
				app.destroyed.delete(0)
				// remplacer l'element
			}
			mut place_chunk := app.get_chunk_at_coords(x, y)
			if place_chunk.tiles[math.abs(y-place_chunk.y*16)][math.abs(x-place_chunk.x*16)] < 0 {
				place_chunk.tiles[math.abs(y-place_chunk.y*16)][math.abs(x-place_chunk.x*16)] = id
			} else {
				return error("Not in an empty space")
			}

			mut chunk := app.get_chunk_at_coords(x-1, y)
			left := chunk.tiles[math.abs(y-chunk.y*16)][math.abs(x-1-chunk.x*16)]
			chunk = app.get_chunk_at_coords(x+1, y)
			right := chunk.tiles[math.abs(y-chunk.y*16)][math.abs(x+1-chunk.x*16)]
			chunk = app.get_chunk_at_coords(x, y-1)
			top := chunk.tiles[math.abs(y-1-chunk.y*16)][math.abs(x-chunk.x*16)]
			chunk = app.get_chunk_at_coords(x, y+1)		
			bot := chunk.tiles[math.abs(y+1-chunk.y*16)][math.abs(x-chunk.x*16)]

			mut glob_wire_ids := []i64{}
			mut inputs :=  []i64{}
			mut outputs :=  []i64{}
			if left >= 0 {
				mut left_elem := &app.elements[left]
				if !left_elem.destroyed {
					if mut left_elem is Wire {
						glob_wire_ids << left_elem.id_glob_wire
					} else if mut left_elem is Not {
						match left_elem.orientation {
							.east {
								if left_elem.state {
									inputs << left
								}
								left_elem.output = id
							}
							.west {
								outputs << left
							}
							else{}
						}
					}
				}
			}
			if right >= 0 {
				mut right_elem := &app.elements[right]
				if !right_elem.destroyed {
					if mut right_elem is Wire {
						glob_wire_ids << right_elem.id_glob_wire
					} else if mut right_elem is Not {
						match right_elem.orientation {
							.west {
								if right_elem.state {
									inputs << right
								}
								right_elem.output = id
							}
							.east {
								outputs << right
							}
							else{}
						}
					}
				}
			}
			if top >= 0 {
				mut top_elem := &app.elements[top]
				if !top_elem.destroyed {
					if mut top_elem is Wire {
						glob_wire_ids << top_elem.id_glob_wire
					} else if mut top_elem is Not {
						match top_elem.orientation {
							.south {
								if top_elem.state {
									inputs << top
								}
								top_elem.output = id
							}
							.north {
								outputs << top
							}
							else{}
						}
					}
				}
			}
			if bot >= 0 {
				mut bot_elem := &app.elements[bot]
				if !bot_elem.destroyed {
					if mut bot_elem is Wire {
						glob_wire_ids << bot_elem.id_glob_wire
					} else if mut bot_elem is Not {
						match bot_elem.orientation {
							.north {
								if bot_elem.state {
									inputs << bot
								}
								bot_elem.output = id
							} 
							.south {
								outputs << bot
							}
							else{}
						}
					}
				}
			}
			mut glob_wire_id := i64(0)
			if glob_wire_ids.len == 0 {
				println('new glob wire')
				glob_wire_id = app.wire_groups.len
				app.wire_groups << GlobalWire {
					state: inputs.len > 0
					wires: [id]
					inputs: inputs
					outputs: outputs
				}
				if outputs.len > 0 {
					app.queue_gwires << glob_wire_id
				}
			} else if glob_wire_ids.len == 1 {
				glob_wire_id = glob_wire_ids[0]
				app.wire_groups[glob_wire_id].wires << id
				app.wire_groups[glob_wire_id].inputs << inputs
				app.wire_groups[glob_wire_id].outputs << outputs
				if app.wire_groups[glob_wire_id].inputs.len > 0 {
					app.wire_groups[glob_wire_id].state = true
					if app.wire_groups[glob_wire_id].inputs.len == inputs.len {
						app.queue_gwires << glob_wire_id // update all the wire as it changed of state
					} else {
							for id_output in outputs {
							mut elem := &app.elements[id_output]
							if mut elem is Not 	{
								elem.state = false
								app.queue << id_output
							}
						}
					}
				}
			} else {
				mut tmp_map := map[i64]bool{}
				for k in glob_wire_ids {
					tmp_map[k] = false
				}
				glob_wire_ids = tmp_map.keys()
				for i in 1..glob_wire_ids.len {
					app.wire_groups[glob_wire_ids[0]].inputs << app.wire_groups[glob_wire_ids[i]].inputs
					app.wire_groups[glob_wire_ids[0]].outputs << app.wire_groups[glob_wire_ids[i]].outputs
					app.wire_groups[glob_wire_ids[0]].wires << app.wire_groups[glob_wire_ids[i]].wires
				}
				app.wire_groups[glob_wire_ids[0]].inputs << inputs
				app.wire_groups[glob_wire_ids[0]].outputs << outputs
				app.wire_groups[glob_wire_ids[0]].state = app.wire_groups[glob_wire_ids[0]].inputs.len > 0
				if app.wire_groups[glob_wire_ids[0]].state {
					for id_output in outputs {
						mut elem := &app.elements[id_output]
						if mut elem is Not {
							elem.state = false
							app.queue << id_output
						}
					}
					for i in 1..glob_wire_ids.len {
						for id_output in app.wire_groups[glob_wire_ids[i]].outputs {
							mut elem := &app.elements[id_output]
							if mut elem is Not {
								elem.state = false
								app.queue << id_output
							}
						}
						
					}
				}
				for i in 1..glob_wire_ids.len {
					app.wire_groups.delete(glob_wire_ids[i])
					for mut j in glob_wire_ids {
						if j > glob_wire_ids[i] {
							j -= 1
						}
					}
				}
				for id_wire in app.wire_groups[glob_wire_ids[0]].wires {
					mut elem := &app.elements[id_wire]
					if mut elem is Wire {
						elem.id_glob_wire = glob_wire_ids[0]
					}else{
						panic("Not a wire in a wiregroup")
					}
				}
				app.wire_groups[glob_wire_ids[0]].wires << id
				glob_wire_id = glob_wire_ids[0]
			}

			if id == app.elements.len {
				app.elements << Wire {
					id_glob_wire: glob_wire_id
					destroyed: false
					in_gate: false
					x: x
					y: y				
				}
			} else {
				app.elements[id] = Wire {
					id_glob_wire: glob_wire_id
					destroyed: false
					in_gate: false
					x: x
					y: y				
				}
			}
		}
	}
}

fn (mut app App) get_chunk_at_coords(x int, y int) &Chunk {
	chunk_y := int(math.floor(f64(y)/16.0))
	chunk_x := int(math.floor(f64(x)/16.0))
	for chunk in app.chunks {
		if chunk.x == chunk_x && chunk.y == chunk_y {
			return &chunk
		}
	}
	app.chunks << Chunk{chunk_x, chunk_y, [][]i64{len:16, init:[]i64{len:16, init:-1}}}
	println("New chunk $chunk_x $chunk_y")
	return &app.chunks[app.chunks.len-1]
}

fn mouse_to_coords(x f32, y f32) (int, int) {
	return int(x)/tile_size, int(y)/tile_size
}