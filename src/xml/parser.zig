const std = @import("std");
const Allocator = std.mem.Allocator;

pub const XmlError = error{
    UnexpectedEndOfInput,
    InvalidXmlDeclaration,
    InvalidElement,
    InvalidAttribute,
    MissingClosingTag,
    UnmatchedClosingTag,
    InvalidCharacter,
    OutOfMemory,
};

pub const NodeType = enum {
    element,
    text,
    comment,
    cdata,
};

pub const Attribute = struct {
    name: []const u8,
    value: []const u8,
};

pub const Node = struct {
    node_type: NodeType,
    name: ?[]const u8,
    value: ?[]const u8,
    attributes: std.ArrayList(Attribute),
    children: std.ArrayList(*Node),
    allocator: Allocator,

    pub fn init(allocator: Allocator, node_type: NodeType) !*Node {
        const node = try allocator.create(Node);
        node.* = .{
            .node_type = node_type,
            .name = null,
            .value = null,
            .attributes = .{},
            .children = .{},
            .allocator = allocator,
        };
        return node;
    }

    pub fn deinit(self: *Node) void {
        for (self.children.items) |child| {
            child.deinit();
        }
        self.children.deinit(self.allocator);
        self.attributes.deinit(self.allocator);
        self.allocator.destroy(self);
    }

    pub fn addAttribute(self: *Node, name: []const u8, value: []const u8) !void {
        try self.attributes.append(self.allocator, .{ .name = name, .value = value });
    }

    pub fn addChild(self: *Node, child: *Node) !void {
        try self.children.append(self.allocator, child);
    }
};

pub const Parser = struct {
    input: []const u8,
    position: usize,
    allocator: Allocator,

    pub fn init(allocator: Allocator, input: []const u8) Parser {
        return .{
            .input = input,
            .position = 0,
            .allocator = allocator,
        };
    }

    pub fn parse(self: *Parser) !*Node {
        self.skipWhitespace();

        // Skip XML declaration and any processing instructions
        while (self.peek(2)) |text| {
            if (std.mem.eql(u8, text, "<?")) {
                try self.skipProcessingInstruction();
                self.skipWhitespace();
            } else {
                break;
            }
        }

        return try self.parseElement();
    }

    fn parseElement(self: *Parser) XmlError!*Node {
        if (!self.expect('<')) return XmlError.InvalidElement;

        // Check for comment
        if (self.peek(3)) |text| {
            if (std.mem.eql(u8, text, "!--")) {
                return try self.parseComment();
            }
        }

        // Check for CDATA
        if (self.peek(8)) |text| {
            if (std.mem.eql(u8, text, "![CDATA[")) {
                return try self.parseCData();
            }
        }

        const name = try self.parseName();
        const node = try Node.init(self.allocator, .element);
        errdefer node.deinit();

        node.name = name;

        self.skipWhitespace();

        // Parse attributes
        while (self.current()) |c| {
            if (c == '>' or (c == '/' and self.peekChar(1) == '>')) break;

            const attr_name = try self.parseName();
            self.skipWhitespace();

            if (!self.expect('=')) return XmlError.InvalidAttribute;

            self.skipWhitespace();
            const attr_value = try self.parseAttributeValue();

            try node.addAttribute(attr_name, attr_value);
            self.skipWhitespace();
        }

        // Check for self-closing tag
        if (self.peek(2)) |text| {
            if (std.mem.eql(u8, text, "/>")) {
                self.position += 2;
                return node;
            }
        }

        if (!self.expect('>')) return XmlError.InvalidElement;

        // Parse children (content)
        while (true) {
            self.skipWhitespace();

            if (self.peek(2)) |text| {
                if (std.mem.eql(u8, text, "</")) {
                    break;
                }
            }

            if (self.current() == null) return XmlError.MissingClosingTag;

            if (self.current() == '<') {
                const child = try self.parseElement();
                try node.addChild(child);
            } else {
                const text_node = try self.parseText();
                if (text_node.value) |val| {
                    if (val.len > 0) {
                        try node.addChild(text_node);
                    } else {
                        text_node.deinit();
                    }
                } else {
                    text_node.deinit();
                }
            }
        }

        // Parse closing tag
        if (!self.expect('<')) return XmlError.MissingClosingTag;
        if (!self.expect('/')) return XmlError.MissingClosingTag;

        const closing_name = try self.parseName();
        if (!std.mem.eql(u8, name, closing_name)) return XmlError.UnmatchedClosingTag;

        self.skipWhitespace();
        if (!self.expect('>')) return XmlError.MissingClosingTag;

        return node;
    }

    fn parseText(self: *Parser) !*Node {
        const start = self.position;
        while (self.current()) |c| {
            if (c == '<') break;
            self.position += 1;
        }

        const node = try Node.init(self.allocator, .text);
        const text = self.input[start..self.position];
        node.value = std.mem.trim(u8, text, &std.ascii.whitespace);
        return node;
    }

    fn parseComment(self: *Parser) !*Node {
        // Skip "!--"
        self.position += 3;

        const start = self.position;
        while (true) {
            if (self.peek(3)) |text| {
                if (std.mem.eql(u8, text, "-->")) {
                    const node = try Node.init(self.allocator, .comment);
                    node.value = self.input[start..self.position];
                    self.position += 3;
                    return node;
                }
            }
            if (self.current() == null) return XmlError.UnexpectedEndOfInput;
            self.position += 1;
        }
    }

    fn parseCData(self: *Parser) !*Node {
        // Skip "![CDATA["
        self.position += 8;

        const start = self.position;
        while (true) {
            if (self.peek(3)) |text| {
                if (std.mem.eql(u8, text, "]]>")) {
                    const node = try Node.init(self.allocator, .cdata);
                    node.value = self.input[start..self.position];
                    self.position += 3;
                    return node;
                }
            }
            if (self.current() == null) return XmlError.UnexpectedEndOfInput;
            self.position += 1;
        }
    }

    fn parseName(self: *Parser) ![]const u8 {
        const start = self.position;
        while (self.current()) |c| {
            if (std.ascii.isAlphanumeric(c) or c == '_' or c == ':' or c == '-' or c == '.') {
                self.position += 1;
            } else {
                break;
            }
        }
        if (self.position == start) return XmlError.InvalidElement;
        return self.input[start..self.position];
    }

    fn parseAttributeValue(self: *Parser) ![]const u8 {
        const quote = self.current() orelse return XmlError.InvalidAttribute;
        if (quote != '"' and quote != '\'') return XmlError.InvalidAttribute;

        self.position += 1;
        const start = self.position;

        while (self.current()) |c| {
            if (c == quote) {
                const value = self.input[start..self.position];
                self.position += 1;
                return value;
            }
            self.position += 1;
        }

        return XmlError.InvalidAttribute;
    }

    fn skipProcessingInstruction(self: *Parser) !void {
        // Skip the opening <?
        self.position += 2;
        
        while (true) {
            if (self.peek(2)) |text| {
                if (std.mem.eql(u8, text, "?>")) {
                    self.position += 2;
                    return;
                }
            }
            if (self.current() == null) return XmlError.InvalidXmlDeclaration;
            self.position += 1;
        }
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.current()) |c| {
            if (!std.ascii.isWhitespace(c)) break;
            self.position += 1;
        }
    }

    fn current(self: *Parser) ?u8 {
        if (self.position >= self.input.len) return null;
        return self.input[self.position];
    }

    fn peek(self: *Parser, len: usize) ?[]const u8 {
        const end = self.position + len;
        if (end > self.input.len) return null;
        return self.input[self.position..end];
    }

    fn peekChar(self: *Parser, offset: usize) ?u8 {
        const pos = self.position + offset;
        if (pos >= self.input.len) return null;
        return self.input[pos];
    }

    fn expect(self: *Parser, expected: u8) bool {
        if (self.current()) |c| {
            if (c == expected) {
                self.position += 1;
                return true;
            }
        }
        return false;
    }
};

// Tests
test "parse simple element" {
    const allocator = std.testing.allocator;

    const xml = "<root></root>";
    var parser = Parser.init(allocator, xml);
    const node = try parser.parse();
    defer node.deinit();

    try std.testing.expect(node.node_type == .element);
    try std.testing.expectEqualStrings("root", node.name.?);
    try std.testing.expect(node.children.items.len == 0);
}

test "parse element with attributes" {
    const allocator = std.testing.allocator;

    const xml = "<root attr1=\"value1\" attr2=\"value2\"></root>";
    var parser = Parser.init(allocator, xml);
    const node = try parser.parse();
    defer node.deinit();

    try std.testing.expect(node.node_type == .element);
    try std.testing.expectEqualStrings("root", node.name.?);
    try std.testing.expect(node.attributes.items.len == 2);
    try std.testing.expectEqualStrings("attr1", node.attributes.items[0].name);
    try std.testing.expectEqualStrings("value1", node.attributes.items[0].value);
    try std.testing.expectEqualStrings("attr2", node.attributes.items[1].name);
    try std.testing.expectEqualStrings("value2", node.attributes.items[1].value);
}

test "parse self-closing element" {
    const allocator = std.testing.allocator;

    const xml = "<root/>";
    var parser = Parser.init(allocator, xml);
    const node = try parser.parse();
    defer node.deinit();

    try std.testing.expect(node.node_type == .element);
    try std.testing.expectEqualStrings("root", node.name.?);
    try std.testing.expect(node.children.items.len == 0);
}

test "parse element with text content" {
    const allocator = std.testing.allocator;

    const xml = "<root>Hello, World!</root>";
    var parser = Parser.init(allocator, xml);
    const node = try parser.parse();
    defer node.deinit();

    try std.testing.expect(node.node_type == .element);
    try std.testing.expectEqualStrings("root", node.name.?);
    try std.testing.expect(node.children.items.len == 1);
    try std.testing.expect(node.children.items[0].node_type == .text);
    try std.testing.expectEqualStrings("Hello, World!", node.children.items[0].value.?);
}

test "parse nested elements" {
    const allocator = std.testing.allocator;

    const xml = "<root><child1><grandchild/></child1><child2/></root>";
    var parser = Parser.init(allocator, xml);
    const node = try parser.parse();
    defer node.deinit();

    try std.testing.expect(node.node_type == .element);
    try std.testing.expectEqualStrings("root", node.name.?);
    try std.testing.expect(node.children.items.len == 2);
    try std.testing.expectEqualStrings("child1", node.children.items[0].name.?);
    try std.testing.expectEqualStrings("child2", node.children.items[1].name.?);
    try std.testing.expect(node.children.items[0].children.items.len == 1);
    try std.testing.expectEqualStrings("grandchild", node.children.items[0].children.items[0].name.?);
}

test "parse element with XML declaration" {
    const allocator = std.testing.allocator;

    const xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><root></root>";
    var parser = Parser.init(allocator, xml);
    const node = try parser.parse();
    defer node.deinit();

    try std.testing.expect(node.node_type == .element);
    try std.testing.expectEqualStrings("root", node.name.?);
}

test "parse comment" {
    const allocator = std.testing.allocator;

    const xml = "<root><!-- This is a comment --></root>";
    var parser = Parser.init(allocator, xml);
    const node = try parser.parse();
    defer node.deinit();

    try std.testing.expect(node.node_type == .element);
    try std.testing.expect(node.children.items.len == 1);
    try std.testing.expect(node.children.items[0].node_type == .comment);
    try std.testing.expectEqualStrings(" This is a comment ", node.children.items[0].value.?);
}

test "parse CDATA" {
    const allocator = std.testing.allocator;

    const xml = "<root><![CDATA[Some <data> & stuff]]></root>";
    var parser = Parser.init(allocator, xml);
    const node = try parser.parse();
    defer node.deinit();

    try std.testing.expect(node.node_type == .element);
    try std.testing.expect(node.children.items.len == 1);
    try std.testing.expect(node.children.items[0].node_type == .cdata);
    try std.testing.expectEqualStrings("Some <data> & stuff", node.children.items[0].value.?);
}

test "parse complex XML document" {
    const allocator = std.testing.allocator;

    const xml =
        \\<?xml version="1.0"?>
        \\<catalog>
        \\  <book id="bk101">
        \\    <author>Gambardella, Matthew</author>
        \\    <title>XML Developer's Guide</title>
        \\    <price>44.95</price>
        \\  </book>
        \\  <book id="bk102">
        \\    <author>Ralls, Kim</author>
        \\    <title>Midnight Rain</title>
        \\    <price>5.95</price>
        \\  </book>
        \\</catalog>
    ;

    var parser = Parser.init(allocator, xml);
    const node = try parser.parse();
    defer node.deinit();

    try std.testing.expectEqualStrings("catalog", node.name.?);
    try std.testing.expect(node.children.items.len == 2);

    const book1 = node.children.items[0];
    try std.testing.expectEqualStrings("book", book1.name.?);
    try std.testing.expect(book1.attributes.items.len == 1);
    try std.testing.expectEqualStrings("id", book1.attributes.items[0].name);
    try std.testing.expectEqualStrings("bk101", book1.attributes.items[0].value);
    try std.testing.expect(book1.children.items.len == 3);
}

test "error on unmatched closing tag" {
    const allocator = std.testing.allocator;

    const xml = "<root><child></wrong></root>";
    var parser = Parser.init(allocator, xml);
    const result = parser.parse();
    try std.testing.expectError(XmlError.UnmatchedClosingTag, result);
}

test "error on missing closing tag" {
    const allocator = std.testing.allocator;

    const xml = "<root><child></root>";
    var parser = Parser.init(allocator, xml);
    const result = parser.parse();
    try std.testing.expectError(XmlError.UnmatchedClosingTag, result);
}

test "parse element with processing instruction" {
    const allocator = std.testing.allocator;

    const xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><?xml-stylesheet href=\"style.xsl\" type=\"text/xsl\"?><root><child>test</child></root>";
    var parser = Parser.init(allocator, xml);
    const node = try parser.parse();
    defer node.deinit();

    try std.testing.expect(node.node_type == .element);
    try std.testing.expectEqualStrings("root", node.name.?);
    try std.testing.expect(node.children.items.len == 1);
    try std.testing.expectEqualStrings("child", node.children.items[0].name.?);
}
