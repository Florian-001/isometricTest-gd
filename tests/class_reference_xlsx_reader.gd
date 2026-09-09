extends RefCounted
## Read-only inspection of the generated workbook, independent of its exporter.


static func cells(path: String) -> Dictionary:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return {}
	var parser := XMLParser.new()
	if parser.open_buffer(zip.read_file("xl/worksheets/sheet1.xml")) != OK:
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
	return "\n".join(cells(path).values().map(func(value: Variant) -> String: return str(value)))


static func part(path: String, name: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(path) != OK:
		return ""
	var content := zip.read_file(name).get_string_from_utf8()
	zip.close()
	return content
