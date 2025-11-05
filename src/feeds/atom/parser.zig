const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("xml");

pub const AtomError = error{
    InvalidAtomFeed,
    MissingRequiredField,
    OutOfMemory,
};

pub const AtomLink = struct {
    href: []const u8,
    rel: ?[]const u8 = null,
    type: ?[]const u8 = null,
};

pub const AtomPerson = struct {
    name: []const u8,
    email: ?[]const u8 = null,
    uri: ?[]const u8 = null,
};

pub const AtomEntry = struct {
    id: []const u8,
    title: []const u8,
    updated: []const u8,
    published: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    content: ?[]const u8 = null,
    links: std.ArrayList(AtomLink),
    authors: std.ArrayList(AtomPerson),
    categories: std.ArrayList([]const u8),

    pub fn deinit(self: *AtomEntry, allocator: Allocator) void {
        self.links.deinit(allocator);
        self.authors.deinit(allocator);
        self.categories.deinit(allocator);
    }
};

pub const AtomFeed = struct {
    id: []const u8,
    title: []const u8,
    updated: []const u8,
    subtitle: ?[]const u8 = null,
    links: std.ArrayList(AtomLink),
    authors: std.ArrayList(AtomPerson),
    entries: std.ArrayList(AtomEntry),
    allocator: Allocator,

    pub fn deinit(self: *AtomFeed) void {
        self.links.deinit(self.allocator);
        self.authors.deinit(self.allocator);
        for (self.entries.items) |*entry| {
            entry.deinit(self.allocator);
        }
        self.entries.deinit(self.allocator);
    }
};

pub const Parser = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Parser {
        return .{ .allocator = allocator };
    }

    pub fn parse(self: *Parser, input: []const u8) !AtomFeed {
        var xml_parser = xml.Parser.init(self.allocator, input);
        const root = try xml_parser.parse();
        defer root.deinit();

        return try self.parseAtom(root);
    }

    fn parseAtom(self: *Parser, root: *xml.Node) !AtomFeed {
        if (root.node_type != .element) return AtomError.InvalidAtomFeed;
        if (root.name == null or !std.mem.eql(u8, root.name.?, "feed")) {
            return AtomError.InvalidAtomFeed;
        }

        var id: ?[]const u8 = null;
        var title: ?[]const u8 = null;
        var updated: ?[]const u8 = null;
        var subtitle: ?[]const u8 = null;
        var links = std.ArrayList(AtomLink){};
        var authors = std.ArrayList(AtomPerson){};
        var entries = std.ArrayList(AtomEntry){};

        for (root.children.items) |child| {
            if (child.node_type != .element or child.name == null) continue;

            const name = child.name.?;

            if (std.mem.eql(u8, name, "id")) {
                id = self.getTextContent(child);
            } else if (std.mem.eql(u8, name, "title")) {
                title = self.getTextContent(child);
            } else if (std.mem.eql(u8, name, "updated")) {
                updated = self.getTextContent(child);
            } else if (std.mem.eql(u8, name, "subtitle")) {
                subtitle = self.getTextContent(child);
            } else if (std.mem.eql(u8, name, "link")) {
                const link = try self.parseLink(child);
                try links.append(self.allocator, link);
            } else if (std.mem.eql(u8, name, "author")) {
                const author = try self.parsePerson(child);
                try authors.append(self.allocator, author);
            } else if (std.mem.eql(u8, name, "entry")) {
                const entry = try self.parseEntry(child);
                try entries.append(self.allocator, entry);
            }
        }

        if (id == null or title == null or updated == null) {
            links.deinit(self.allocator);
            authors.deinit(self.allocator);
            for (entries.items) |*entry| {
                entry.deinit(self.allocator);
            }
            entries.deinit(self.allocator);
            return AtomError.MissingRequiredField;
        }

        return AtomFeed{
            .id = id.?,
            .title = title.?,
            .updated = updated.?,
            .subtitle = subtitle,
            .links = links,
            .authors = authors,
            .entries = entries,
            .allocator = self.allocator,
        };
    }

    fn parseEntry(self: *Parser, node: *xml.Node) !AtomEntry {
        var id: ?[]const u8 = null;
        var title: ?[]const u8 = null;
        var updated: ?[]const u8 = null;
        var published: ?[]const u8 = null;
        var summary: ?[]const u8 = null;
        var content: ?[]const u8 = null;
        var links = std.ArrayList(AtomLink){};
        var authors = std.ArrayList(AtomPerson){};
        var categories = std.ArrayList([]const u8){};

        for (node.children.items) |child| {
            if (child.node_type != .element or child.name == null) continue;

            const name = child.name.?;

            if (std.mem.eql(u8, name, "id")) {
                id = self.getTextContent(child);
            } else if (std.mem.eql(u8, name, "title")) {
                title = self.getTextContent(child);
            } else if (std.mem.eql(u8, name, "updated")) {
                updated = self.getTextContent(child);
            } else if (std.mem.eql(u8, name, "published")) {
                published = self.getTextContent(child);
            } else if (std.mem.eql(u8, name, "summary")) {
                summary = self.getTextContent(child);
            } else if (std.mem.eql(u8, name, "content")) {
                content = self.getTextContent(child);
            } else if (std.mem.eql(u8, name, "link")) {
                const link = try self.parseLink(child);
                try links.append(self.allocator, link);
            } else if (std.mem.eql(u8, name, "author")) {
                const author = try self.parsePerson(child);
                try authors.append(self.allocator, author);
            } else if (std.mem.eql(u8, name, "category")) {
                if (self.getAttribute(child, "term")) |term| {
                    try categories.append(self.allocator, term);
                }
            }
        }

        if (id == null or title == null or updated == null) {
            links.deinit(self.allocator);
            authors.deinit(self.allocator);
            categories.deinit(self.allocator);
            return AtomError.MissingRequiredField;
        }

        return AtomEntry{
            .id = id.?,
            .title = title.?,
            .updated = updated.?,
            .published = published,
            .summary = summary,
            .content = content,
            .links = links,
            .authors = authors,
            .categories = categories,
        };
    }

    fn parseLink(self: *Parser, node: *xml.Node) !AtomLink {
        const href = self.getAttribute(node, "href") orelse return AtomError.MissingRequiredField;
        const rel = self.getAttribute(node, "rel");
        const link_type = self.getAttribute(node, "type");

        return AtomLink{
            .href = href,
            .rel = rel,
            .type = link_type,
        };
    }

    fn parsePerson(self: *Parser, node: *xml.Node) !AtomPerson {
        var name: ?[]const u8 = null;
        var email: ?[]const u8 = null;
        var uri: ?[]const u8 = null;

        for (node.children.items) |child| {
            if (child.node_type != .element or child.name == null) continue;

            const child_name = child.name.?;

            if (std.mem.eql(u8, child_name, "name")) {
                name = self.getTextContent(child);
            } else if (std.mem.eql(u8, child_name, "email")) {
                email = self.getTextContent(child);
            } else if (std.mem.eql(u8, child_name, "uri")) {
                uri = self.getTextContent(child);
            }
        }

        if (name == null) return AtomError.MissingRequiredField;

        return AtomPerson{
            .name = name.?,
            .email = email,
            .uri = uri,
        };
    }

    fn getTextContent(self: *Parser, node: *xml.Node) ?[]const u8 {
        _ = self;
        for (node.children.items) |child| {
            if (child.node_type == .text and child.value != null) {
                return child.value.?;
            } else if (child.node_type == .cdata and child.value != null) {
                return child.value.?;
            }
        }
        return null;
    }

    fn getAttribute(self: *Parser, node: *xml.Node, attr_name: []const u8) ?[]const u8 {
        _ = self;
        for (node.attributes.items) |attr| {
            if (std.mem.eql(u8, attr.name, attr_name)) {
                return attr.value;
            }
        }
        return null;
    }
};

// Tests
test "parse minimal Atom feed" {
    const allocator = std.testing.allocator;

    const atom_xml =
        \\<?xml version="1.0" encoding="utf-8"?>
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <id>urn:uuid:12345</id>
        \\  <title>Test Atom Feed</title>
        \\  <updated>2024-01-01T00:00:00Z</updated>
        \\</feed>
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(atom_xml);
    defer feed.deinit();

    try std.testing.expectEqualStrings("urn:uuid:12345", feed.id);
    try std.testing.expectEqualStrings("Test Atom Feed", feed.title);
    try std.testing.expectEqualStrings("2024-01-01T00:00:00Z", feed.updated);
}

test "parse Atom feed with entries" {
    const allocator = std.testing.allocator;

    const atom_xml =
        \\<?xml version="1.0"?>
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <id>urn:uuid:feed-id</id>
        \\  <title>My Blog</title>
        \\  <updated>2024-01-01T00:00:00Z</updated>
        \\  <entry>
        \\    <id>urn:uuid:entry-1</id>
        \\    <title>First Entry</title>
        \\    <updated>2024-01-01T00:00:00Z</updated>
        \\    <summary>This is the first entry</summary>
        \\  </entry>
        \\  <entry>
        \\    <id>urn:uuid:entry-2</id>
        \\    <title>Second Entry</title>
        \\    <updated>2024-01-02T00:00:00Z</updated>
        \\    <published>2024-01-02T00:00:00Z</published>
        \\  </entry>
        \\</feed>
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(atom_xml);
    defer feed.deinit();

    try std.testing.expect(feed.entries.items.len == 2);
    
    const entry1 = feed.entries.items[0];
    try std.testing.expectEqualStrings("urn:uuid:entry-1", entry1.id);
    try std.testing.expectEqualStrings("First Entry", entry1.title);
    try std.testing.expectEqualStrings("This is the first entry", entry1.summary.?);

    const entry2 = feed.entries.items[1];
    try std.testing.expectEqualStrings("urn:uuid:entry-2", entry2.id);
    try std.testing.expectEqualStrings("2024-01-02T00:00:00Z", entry2.published.?);
}

test "parse Atom feed with links" {
    const allocator = std.testing.allocator;

    const atom_xml =
        \\<?xml version="1.0"?>
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <id>urn:uuid:feed-id</id>
        \\  <title>My Blog</title>
        \\  <updated>2024-01-01T00:00:00Z</updated>
        \\  <link href="https://example.com/" rel="alternate" type="text/html"/>
        \\  <link href="https://example.com/feed.atom" rel="self" type="application/atom+xml"/>
        \\</feed>
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(atom_xml);
    defer feed.deinit();

    try std.testing.expect(feed.links.items.len == 2);
    
    const link1 = feed.links.items[0];
    try std.testing.expectEqualStrings("https://example.com/", link1.href);
    try std.testing.expectEqualStrings("alternate", link1.rel.?);
    try std.testing.expectEqualStrings("text/html", link1.type.?);

    const link2 = feed.links.items[1];
    try std.testing.expectEqualStrings("https://example.com/feed.atom", link2.href);
    try std.testing.expectEqualStrings("self", link2.rel.?);
}

test "parse Atom feed with author" {
    const allocator = std.testing.allocator;

    const atom_xml =
        \\<?xml version="1.0"?>
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <id>urn:uuid:feed-id</id>
        \\  <title>My Blog</title>
        \\  <updated>2024-01-01T00:00:00Z</updated>
        \\  <author>
        \\    <name>John Doe</name>
        \\    <email>john@example.com</email>
        \\    <uri>https://johndoe.com</uri>
        \\  </author>
        \\</feed>
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(atom_xml);
    defer feed.deinit();

    try std.testing.expect(feed.authors.items.len == 1);
    const author = feed.authors.items[0];
    try std.testing.expectEqualStrings("John Doe", author.name);
    try std.testing.expectEqualStrings("john@example.com", author.email.?);
    try std.testing.expectEqualStrings("https://johndoe.com", author.uri.?);
}

test "parse Atom entry with content and categories" {
    const allocator = std.testing.allocator;

    const atom_xml =
        \\<?xml version="1.0"?>
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <id>urn:uuid:feed-id</id>
        \\  <title>My Blog</title>
        \\  <updated>2024-01-01T00:00:00Z</updated>
        \\  <entry>
        \\    <id>urn:uuid:entry-1</id>
        \\    <title>First Entry</title>
        \\    <updated>2024-01-01T00:00:00Z</updated>
        \\    <content>Full content here</content>
        \\    <category term="technology"/>
        \\    <category term="programming"/>
        \\  </entry>
        \\</feed>
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(atom_xml);
    defer feed.deinit();

    try std.testing.expect(feed.entries.items.len == 1);
    const entry = feed.entries.items[0];
    try std.testing.expectEqualStrings("Full content here", entry.content.?);
    try std.testing.expect(entry.categories.items.len == 2);
    try std.testing.expectEqualStrings("technology", entry.categories.items[0]);
    try std.testing.expectEqualStrings("programming", entry.categories.items[1]);
}

test "error on invalid Atom structure" {
    const allocator = std.testing.allocator;

    const invalid_xml =
        \\<?xml version="1.0"?>
        \\<rss version="2.0">
        \\  <channel>
        \\    <title>Not Atom</title>
        \\  </channel>
        \\</rss>
    ;

    var parser = Parser.init(allocator);
    try std.testing.expectError(AtomError.InvalidAtomFeed, parser.parse(invalid_xml));
}

test "error on missing required feed fields" {
    const allocator = std.testing.allocator;

    const invalid_xml =
        \\<?xml version="1.0"?>
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <title>Incomplete Feed</title>
        \\</feed>
    ;

    var parser = Parser.init(allocator);
    try std.testing.expectError(AtomError.MissingRequiredField, parser.parse(invalid_xml));
}
