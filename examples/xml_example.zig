const std = @import("std");
const xml = @import("parser.zig");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const xml_string =
        \\<?xml version="1.0" encoding="UTF-8"?>
        \\<catalog>
        \\  <book id="bk101" category="programming">
        \\    <author>Gambardella, Matthew</author>
        \\    <title>XML Developer's Guide</title>
        \\    <price currency="USD">44.95</price>
        \\    <description>An in-depth look at creating applications with XML.</description>
        \\  </book>
        \\  <book id="bk102" category="fiction">
        \\    <author>Ralls, Kim</author>
        \\    <title>Midnight Rain</title>
        \\    <price currency="USD">5.95</price>
        \\    <description><![CDATA[A former architect battles corporate zombies & <evil> entities.]]></description>
        \\  </book>
        \\  <!-- More books could be added here -->
        \\</catalog>
    ;

    std.debug.print("Parsing XML document...\n\n", .{});

    var parser = xml.Parser.init(allocator, xml_string);
    const root = try parser.parse();
    defer root.deinit();

    // Print root element
    std.debug.print("Root element: {s}\n\n", .{root.name.?});

    // Iterate through books
    for (root.children.items) |child| {
        if (child.node_type == .element) {
            std.debug.print("Book: {s}\n", .{child.name.?});

            // Print attributes
            for (child.attributes.items) |attr| {
                std.debug.print("  @{s} = \"{s}\"\n", .{ attr.name, attr.value });
            }

            // Print child elements
            for (child.children.items) |field| {
                if (field.node_type == .element) {
                    std.debug.print("  {s}: ", .{field.name.?});

                    // Print attributes if any
                    for (field.attributes.items) |attr| {
                        std.debug.print("[@{s}=\"{s}\"] ", .{ attr.name, attr.value });
                    }

                    // Print text or CDATA content
                    for (field.children.items) |content| {
                        if (content.node_type == .text) {
                            std.debug.print("{s}", .{content.value.?});
                        } else if (content.node_type == .cdata) {
                            std.debug.print("{s}", .{content.value.?});
                        }
                    }
                    std.debug.print("\n", .{});
                }
            }
            std.debug.print("\n", .{});
        } else if (child.node_type == .comment) {
            std.debug.print("Comment: {s}\n\n", .{child.value.?});
        }
    }
}
