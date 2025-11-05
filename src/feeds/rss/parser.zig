const std = @import("std");
const Allocator = std.mem.Allocator;
const xml = @import("xml");

pub const RssError = error{
    InvalidRssFeed,
    MissingRequiredField,
    InvalidVersion,
    OutOfMemory,
};

pub const RssItem = struct {
    title: ?[]const u8 = null,
    link: ?[]const u8 = null,
    description: ?[]const u8 = null,
    author: ?[]const u8 = null,
    category: ?[]const u8 = null,
    comments: ?[]const u8 = null,
    enclosure_url: ?[]const u8 = null,
    enclosure_type: ?[]const u8 = null,
    guid: ?[]const u8 = null,
    pub_date: ?[]const u8 = null,
    source: ?[]const u8 = null,

    pub fn deinit(self: *RssItem, allocator: Allocator) void {
        _ = self;
        _ = allocator;
    }
};

pub const RssChannel = struct {
    title: []const u8,
    link: []const u8,
    description: []const u8,
    language: ?[]const u8 = null,
    copyright: ?[]const u8 = null,
    managing_editor: ?[]const u8 = null,
    web_master: ?[]const u8 = null,
    pub_date: ?[]const u8 = null,
    last_build_date: ?[]const u8 = null,
    category: ?[]const u8 = null,
    generator: ?[]const u8 = null,
    ttl: ?[]const u8 = null,
    items: std.ArrayList(RssItem),

    pub fn deinit(self: *RssChannel, allocator: Allocator) void {
        for (self.items.items) |*item| {
            item.deinit(allocator);
        }
        self.items.deinit(allocator);
    }
};

pub const RssFeed = struct {
    version: []const u8,
    channel: RssChannel,
    allocator: Allocator,

    pub fn deinit(self: *RssFeed) void {
        self.channel.deinit(self.allocator);
    }
};

pub const Parser = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Parser {
        return .{ .allocator = allocator };
    }

    pub fn parse(self: *Parser, input: []const u8) !RssFeed {
        var xml_parser = xml.Parser.init(self.allocator, input);
        const root = try xml_parser.parse();
        defer root.deinit();

        return try self.parseRss(root);
    }

    fn parseRss(self: *Parser, root: *xml.Node) !RssFeed {
        if (root.node_type != .element) return RssError.InvalidRssFeed;
        if (root.name == null or !std.mem.eql(u8, root.name.?, "rss")) {
            return RssError.InvalidRssFeed;
        }

        var version: ?[]const u8 = null;
        for (root.attributes.items) |attr| {
            if (std.mem.eql(u8, attr.name, "version")) {
                version = attr.value;
                break;
            }
        }

        if (version == null) return RssError.InvalidVersion;

        var channel_node: ?*xml.Node = null;
        for (root.children.items) |child| {
            if (child.node_type == .element and child.name != null) {
                if (std.mem.eql(u8, child.name.?, "channel")) {
                    channel_node = child;
                    break;
                }
            }
        }

        if (channel_node == null) return RssError.InvalidRssFeed;

        const channel = try self.parseChannel(channel_node.?);

        return RssFeed{
            .version = version.?,
            .channel = channel,
            .allocator = self.allocator,
        };
    }

    fn parseChannel(self: *Parser, node: *xml.Node) !RssChannel {
        var title: ?[]const u8 = null;
        var link: ?[]const u8 = null;
        var description: ?[]const u8 = null;
        var language: ?[]const u8 = null;
        var copyright: ?[]const u8 = null;
        var managing_editor: ?[]const u8 = null;
        var web_master: ?[]const u8 = null;
        var pub_date: ?[]const u8 = null;
        var last_build_date: ?[]const u8 = null;
        var category: ?[]const u8 = null;
        var generator: ?[]const u8 = null;
        var ttl: ?[]const u8 = null;
        var items = std.ArrayList(RssItem){};

        for (node.children.items) |child| {
            if (child.node_type != .element or child.name == null) continue;

            const name = child.name.?;
            const text_value = self.getTextContent(child);

            if (std.mem.eql(u8, name, "title")) {
                title = text_value;
            } else if (std.mem.eql(u8, name, "link")) {
                link = text_value;
            } else if (std.mem.eql(u8, name, "description")) {
                description = text_value;
            } else if (std.mem.eql(u8, name, "language")) {
                language = text_value;
            } else if (std.mem.eql(u8, name, "copyright")) {
                copyright = text_value;
            } else if (std.mem.eql(u8, name, "managingEditor")) {
                managing_editor = text_value;
            } else if (std.mem.eql(u8, name, "webMaster")) {
                web_master = text_value;
            } else if (std.mem.eql(u8, name, "pubDate")) {
                pub_date = text_value;
            } else if (std.mem.eql(u8, name, "lastBuildDate")) {
                last_build_date = text_value;
            } else if (std.mem.eql(u8, name, "category")) {
                category = text_value;
            } else if (std.mem.eql(u8, name, "generator")) {
                generator = text_value;
            } else if (std.mem.eql(u8, name, "ttl")) {
                ttl = text_value;
            } else if (std.mem.eql(u8, name, "item")) {
                const item = try self.parseItem(child);
                try items.append(self.allocator, item);
            }
        }

        if (title == null or link == null or description == null) {
            items.deinit(self.allocator);
            return RssError.MissingRequiredField;
        }

        return RssChannel{
            .title = title.?,
            .link = link.?,
            .description = description.?,
            .language = language,
            .copyright = copyright,
            .managing_editor = managing_editor,
            .web_master = web_master,
            .pub_date = pub_date,
            .last_build_date = last_build_date,
            .category = category,
            .generator = generator,
            .ttl = ttl,
            .items = items,
        };
    }

    fn parseItem(self: *Parser, node: *xml.Node) !RssItem {
        var item = RssItem{};

        for (node.children.items) |child| {
            if (child.node_type != .element or child.name == null) continue;

            const name = child.name.?;
            const text_value = self.getTextContent(child);

            if (std.mem.eql(u8, name, "title")) {
                item.title = text_value;
            } else if (std.mem.eql(u8, name, "link")) {
                item.link = text_value;
            } else if (std.mem.eql(u8, name, "description")) {
                item.description = text_value;
            } else if (std.mem.eql(u8, name, "author")) {
                item.author = text_value;
            } else if (std.mem.eql(u8, name, "category")) {
                item.category = text_value;
            } else if (std.mem.eql(u8, name, "comments")) {
                item.comments = text_value;
            } else if (std.mem.eql(u8, name, "guid")) {
                item.guid = text_value;
            } else if (std.mem.eql(u8, name, "pubDate")) {
                item.pub_date = text_value;
            } else if (std.mem.eql(u8, name, "source")) {
                item.source = text_value;
            } else if (std.mem.eql(u8, name, "enclosure")) {
                for (child.attributes.items) |attr| {
                    if (std.mem.eql(u8, attr.name, "url")) {
                        item.enclosure_url = attr.value;
                    } else if (std.mem.eql(u8, attr.name, "type")) {
                        item.enclosure_type = attr.value;
                    }
                }
            }
        }

        return item;
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
};

// Tests
test "parse minimal RSS 2.0 feed" {
    const allocator = std.testing.allocator;

    const rss_xml =
        \\<?xml version="1.0"?>
        \\<rss version="2.0">
        \\  <channel>
        \\    <title>Test Feed</title>
        \\    <link>https://example.com</link>
        \\    <description>A test RSS feed</description>
        \\  </channel>
        \\</rss>
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(rss_xml);
    defer feed.deinit();

    try std.testing.expectEqualStrings("2.0", feed.version);
    try std.testing.expectEqualStrings("Test Feed", feed.channel.title);
    try std.testing.expectEqualStrings("https://example.com", feed.channel.link);
    try std.testing.expectEqualStrings("A test RSS feed", feed.channel.description);
}

test "parse RSS feed with items" {
    const allocator = std.testing.allocator;

    const rss_xml =
        \\<?xml version="1.0"?>
        \\<rss version="2.0">
        \\  <channel>
        \\    <title>Tech Blog</title>
        \\    <link>https://techblog.com</link>
        \\    <description>Latest tech news</description>
        \\    <item>
        \\      <title>First Post</title>
        \\      <link>https://techblog.com/first</link>
        \\      <description>This is the first post</description>
        \\      <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
        \\    </item>
        \\    <item>
        \\      <title>Second Post</title>
        \\      <link>https://techblog.com/second</link>
        \\      <description>This is the second post</description>
        \\    </item>
        \\  </channel>
        \\</rss>
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(rss_xml);
    defer feed.deinit();

    try std.testing.expect(feed.channel.items.items.len == 2);
    
    const item1 = feed.channel.items.items[0];
    try std.testing.expectEqualStrings("First Post", item1.title.?);
    try std.testing.expectEqualStrings("https://techblog.com/first", item1.link.?);
    try std.testing.expectEqualStrings("Mon, 01 Jan 2024 00:00:00 GMT", item1.pub_date.?);

    const item2 = feed.channel.items.items[1];
    try std.testing.expectEqualStrings("Second Post", item2.title.?);
}

test "parse RSS feed with optional channel fields" {
    const allocator = std.testing.allocator;

    const rss_xml =
        \\<?xml version="1.0"?>
        \\<rss version="2.0">
        \\  <channel>
        \\    <title>News Feed</title>
        \\    <link>https://news.com</link>
        \\    <description>Daily news</description>
        \\    <language>en-us</language>
        \\    <copyright>Copyright 2024</copyright>
        \\    <managingEditor>editor@news.com</managingEditor>
        \\    <webMaster>webmaster@news.com</webMaster>
        \\    <ttl>60</ttl>
        \\  </channel>
        \\</rss>
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(rss_xml);
    defer feed.deinit();

    try std.testing.expectEqualStrings("en-us", feed.channel.language.?);
    try std.testing.expectEqualStrings("Copyright 2024", feed.channel.copyright.?);
    try std.testing.expectEqualStrings("editor@news.com", feed.channel.managing_editor.?);
    try std.testing.expectEqualStrings("webmaster@news.com", feed.channel.web_master.?);
    try std.testing.expectEqualStrings("60", feed.channel.ttl.?);
}

test "parse RSS item with enclosure" {
    const allocator = std.testing.allocator;

    const rss_xml =
        \\<?xml version="1.0"?>
        \\<rss version="2.0">
        \\  <channel>
        \\    <title>Podcast</title>
        \\    <link>https://podcast.com</link>
        \\    <description>My podcast</description>
        \\    <item>
        \\      <title>Episode 1</title>
        \\      <link>https://podcast.com/ep1</link>
        \\      <description>First episode</description>
        \\      <enclosure url="https://podcast.com/ep1.mp3" type="audio/mpeg"/>
        \\    </item>
        \\  </channel>
        \\</rss>
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(rss_xml);
    defer feed.deinit();

    try std.testing.expect(feed.channel.items.items.len == 1);
    const item = feed.channel.items.items[0];
    try std.testing.expectEqualStrings("https://podcast.com/ep1.mp3", item.enclosure_url.?);
    try std.testing.expectEqualStrings("audio/mpeg", item.enclosure_type.?);
}

test "error on invalid RSS structure" {
    const allocator = std.testing.allocator;

    const invalid_xml =
        \\<?xml version="1.0"?>
        \\<feed>
        \\  <title>Not RSS</title>
        \\</feed>
    ;

    var parser = Parser.init(allocator);
    try std.testing.expectError(RssError.InvalidRssFeed, parser.parse(invalid_xml));
}

test "error on missing required channel fields" {
    const allocator = std.testing.allocator;

    const invalid_xml =
        \\<?xml version="1.0"?>
        \\<rss version="2.0">
        \\  <channel>
        \\    <title>Incomplete Feed</title>
        \\  </channel>
        \\</rss>
    ;

    var parser = Parser.init(allocator);
    try std.testing.expectError(RssError.MissingRequiredField, parser.parse(invalid_xml));
}
