extends RefCounted
## Read-only inspection of the generated workbook, independent of its exporter.


static func cells(path: String, sheet_index: int = 1) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {}
	var parser := XMLParser.new()
	if parser.open_buffer(zip.read_file("xl/worksheets/sheet%d.xml" % sheet_index)) != OK:
		zip.close()
		return {}
	var result := {}
	var address := ""
	var type := ""
	var value := ""
	var reading := false
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			var name := parser.get_node_name().split(":")[-1]
			if name == "c":
				address = parser.get_named_attribute_value_safe("r")
				type = parser.get_named_attribute_value_safe("t")
				value = ""
				if parser.is_empty():
					result[address] = null
			elif name == "v" or name == "t":
				reading = true
		elif parser.get_node_type() == XMLParser.NODE_TEXT and reading:
			value += parser.get_node_data()
		elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			var name := parser.get_node_name().split(":")[-1]
			if name == "v" or name == "t":
				reading = false
			elif name == "c":
				result[address] = int(value) if type == "n" else value
	zip.close()
	return result


static func text(path: String) -> String:
	var values: Array = []
	for index in sheet_names(path).size():
		values.append_array(cells(path, index + 1).values())
	return "\n".join(values.map(func(value: Variant) -> String: return str(value)))


static func sheet_names(path: String) -> Array[String]:
	var names: Array[String] = []
	var parser := XMLParser.new()
	var xml := part(path, "xl/workbook.xml")
	if xml.is_empty() or parser.open_buffer(xml.to_utf8_buffer()) != OK:
		return names
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT and parser.get_node_name().split(":")[-1] == "sheet":
			names.append(parser.get_named_attribute_value_safe("name"))
	return names


static func part(path: String, name: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return ""
	var content := zip.read_file(name).get_string_from_utf8()
	zip.close()
	return content
