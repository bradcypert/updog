# XML Parser for Zig

A simple, test-driven XML parser implementation in Zig.

## Features

- Parse XML elements with attributes
- Support for nested elements
- Handle text content
- Parse XML comments
- Parse CDATA sections
- Support self-closing tags
- Handle XML declarations
- Comprehensive error handling

## Usage

```zig
const std = @import("std");
const xml = @import("xml/parser.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xml_string =
        \\<?xml version="1.0"?>
        \\<catalog>
        \\  <book id="bk101">
        \\    <author>Gambardella, Matthew</author>
        \\    <title>XML Developer's Guide</title>
        \\    <price>44.95</price>
        \\  </book>
        \\</catalog>
    ;

    var parser = xml.Parser.init(allocator, xml_string);
    const root = try parser.parse();
    defer root.deinit();

    // Access the parsed data
    std.debug.print("Root element: {s}\n", .{root.name.?});
    for (root.children.items) |child| {
        std.debug.print("Child: {s}\n", .{child.name.?});
    }
}
```

## API

### Parser

- `Parser.init(allocator, input)` - Create a new parser
- `parser.parse()` - Parse the XML and return the root node

### Node

- `Node.init(allocator, node_type)` - Create a new node
- `node.deinit()` - Free the node and all its children
- `node.addAttribute(name, value)` - Add an attribute to the node
- `node.addChild(child)` - Add a child node

### Node Types

- `.element` - XML element
- `.text` - Text content
- `.comment` - XML comment
- `.cdata` - CDATA section

## Running Tests

```bash
zig build test
```

## Error Handling

The parser returns these errors:

- `UnexpectedEndOfInput` - Input ended unexpectedly
- `InvalidXmlDeclaration` - Malformed XML declaration
- `InvalidElement` - Invalid element syntax
- `InvalidAttribute` - Invalid attribute syntax
- `MissingClosingTag` - Missing closing tag
- `UnmatchedClosingTag` - Closing tag doesn't match opening tag
- `InvalidCharacter` - Invalid character in input
