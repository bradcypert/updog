const std = @import("std");
const Allocator = std.mem.Allocator;

const rss = @import("rss");
const atom = @import("atom");
const json_feed = @import("json_feed");

pub const FeedError = error{
    UnknownFeedFormat,
    InvalidFeed,
    OutOfMemory,
};

pub const FeedType = enum {
    rss,
    atom,
    json_feed,
};

pub const FeedItem = struct {
    id: ?[]const u8 = null,
    title: ?[]const u8 = null,
    url: ?[]const u8 = null,
    content_html: ?[]const u8 = null,
    content_text: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    date_published: ?[]const u8 = null,
    date_modified: ?[]const u8 = null,
    author: ?[]const u8 = null,
    tags: std.ArrayList([]const u8),

    pub fn deinit(self: *FeedItem, allocator: Allocator) void {
        self.tags.deinit(allocator);
    }
};

pub const Feed = struct {
    feed_type: FeedType,
    title: []const u8,
    url: ?[]const u8 = null,
    description: ?[]const u8 = null,
    items: std.ArrayList(FeedItem),
    allocator: Allocator,

    // Store original parsed feeds to keep memory valid
    rss_feed: ?rss.RssFeed = null,
    atom_feed: ?atom.AtomFeed = null,
    json_feed_data: ?json_feed.JsonFeed = null,

    pub fn deinit(self: *Feed) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);

        if (self.rss_feed) |*feed| {
            feed.deinit();
        }
        if (self.atom_feed) |*feed| {
            feed.deinit();
        }
        if (self.json_feed_data) |*feed| {
            feed.deinit();
        }
    }
};

pub const Parser = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Parser {
        return .{ .allocator = allocator };
    }

    pub fn parse(self: *Parser, input: []const u8) !Feed {
        const feed_type = try self.detectFeedType(input);

        return switch (feed_type) {
            .rss => try self.parseRss(input),
            .atom => try self.parseAtom(input),
            .json_feed => try self.parseJsonFeed(input),
        };
    }

    fn detectFeedType(self: *Parser, input: []const u8) !FeedType {
        _ = self;

        // Trim leading whitespace
        var start: usize = 0;
        while (start < input.len and std.ascii.isWhitespace(input[start])) {
            start += 1;
        }

        if (start >= input.len) return FeedError.UnknownFeedFormat;

        // Check for JSON
        if (input[start] == '{') {
            return .json_feed;
        }

        // Must be XML - look for RSS or Atom root element
        // Find first element after optional XML declaration
        var pos = start;

        // Skip XML declaration if present
        if (std.mem.indexOf(u8, input[pos..], "<?xml")) |xml_decl_pos| {
            if (xml_decl_pos < 10) { // Should be near the start
                if (std.mem.indexOf(u8, input[pos..], "?>")) |end_pos| {
                    pos += end_pos + 2;
                }
            }
        }

        // Skip whitespace after declaration
        while (pos < input.len and std.ascii.isWhitespace(input[pos])) {
            pos += 1;
        }

        if (pos >= input.len) return FeedError.UnknownFeedFormat;

        // Look for root element
        if (std.mem.indexOf(u8, input[pos..], "<rss")) |_| {
            return .rss;
        }

        if (std.mem.indexOf(u8, input[pos..], "<feed")) |_| {
            return .atom;
        }

        return FeedError.UnknownFeedFormat;
    }

    fn parseRss(self: *Parser, input: []const u8) !Feed {
        var rss_parser = rss.Parser.init(self.allocator);
        var rss_feed = try rss_parser.parse(input);
        errdefer rss_feed.deinit();

        var items: std.ArrayList(FeedItem) = .empty;
        errdefer {
            for (items.items) |*item| {
                item.deinit(self.allocator);
            }
            items.deinit(self.allocator);
        }

        for (rss_feed.channel.items.items) |rss_item| {
            var tags: std.ArrayList([]const u8) = .empty;
            if (rss_item.category) |cat| {
                try tags.append(self.allocator, cat);
            }

            try items.append(self.allocator, .{
                .id = rss_item.guid,
                .title = rss_item.title,
                .url = rss_item.link,
                .content_html = null,
                .content_text = null,
                .summary = rss_item.description,
                .date_published = rss_item.pub_date,
                .date_modified = null,
                .author = rss_item.author,
                .tags = tags,
            });
        }

        return Feed{
            .feed_type = .rss,
            .title = rss_feed.channel.title,
            .url = rss_feed.channel.link,
            .description = rss_feed.channel.description,
            .items = items,
            .allocator = self.allocator,
            .rss_feed = rss_feed,
            .atom_feed = null,
            .json_feed_data = null,
        };
    }

    fn parseAtom(self: *Parser, input: []const u8) !Feed {
        var atom_parser = atom.Parser.init(self.allocator);
        var atom_feed = try atom_parser.parse(input);
        errdefer atom_feed.deinit();

        var items: std.ArrayList(FeedItem) = .empty;
        errdefer {
            for (items.items) |*item| {
                item.deinit(self.allocator);
            }
            items.deinit(self.allocator);
        }

        for (atom_feed.entries.items) |entry| {
            // Find alternate link
            var url: ?[]const u8 = null;
            for (entry.links.items) |link| {
                if (link.rel) |rel| {
                    if (std.mem.eql(u8, rel, "alternate")) {
                        url = link.href;
                        break;
                    }
                } else {
                    url = link.href;
                }
            }

            // Get first author name if available
            var author: ?[]const u8 = null;
            if (entry.authors.items.len > 0) {
                author = entry.authors.items[0].name;
            }

            // Copy categories to tags
            var tags: std.ArrayList([]const u8) = .empty;
            for (entry.categories.items) |category| {
                try tags.append(self.allocator, category);
            }

            try items.append(self.allocator, .{
                .id = entry.id,
                .title = entry.title,
                .url = url,
                .content_html = entry.content,
                .content_text = null,
                .summary = entry.summary,
                .date_published = entry.published,
                .date_modified = entry.updated,
                .author = author,
                .tags = tags,
            });
        }

        // Find feed URL
        var feed_url: ?[]const u8 = null;
        for (atom_feed.links.items) |link| {
            if (link.rel) |rel| {
                if (std.mem.eql(u8, rel, "alternate")) {
                    feed_url = link.href;
                    break;
                }
            }
        }

        return Feed{
            .feed_type = .atom,
            .title = atom_feed.title,
            .url = feed_url,
            .description = atom_feed.subtitle,
            .items = items,
            .allocator = self.allocator,
            .rss_feed = null,
            .atom_feed = atom_feed,
            .json_feed_data = null,
        };
    }

    fn parseJsonFeed(self: *Parser, input: []const u8) !Feed {
        var json_parser = json_feed.Parser.init(self.allocator);
        var json_data = try json_parser.parse(input);
        errdefer json_data.deinit();

        var items: std.ArrayList(FeedItem) = .empty;
        errdefer {
            for (items.items) |*item| {
                item.deinit(self.allocator);
            }
            items.deinit(self.allocator);
        }

        for (json_data.items.items) |json_item| {
            // Get first author name if available
            var author: ?[]const u8 = null;
            if (json_item.authors.items.len > 0) {
                author = json_item.authors.items[0].name;
            }

            // Copy tags
            var tags: std.ArrayList([]const u8) = .empty;
            for (json_item.tags.items) |tag| {
                try tags.append(self.allocator, tag);
            }

            try items.append(self.allocator, .{
                .id = json_item.id,
                .title = json_item.title,
                .url = json_item.url,
                .content_html = json_item.content_html,
                .content_text = json_item.content_text,
                .summary = json_item.summary,
                .date_published = json_item.date_published,
                .date_modified = json_item.date_modified,
                .author = author,
                .tags = tags,
            });
        }

        return Feed{
            .feed_type = .json_feed,
            .title = json_data.title,
            .url = json_data.home_page_url,
            .description = json_data.description,
            .items = items,
            .allocator = self.allocator,
            .rss_feed = null,
            .atom_feed = null,
            .json_feed_data = json_data,
        };
    }
};

// Tests
test "detect RSS feed" {
    const allocator = std.testing.allocator;

    const rss_xml =
        \\<?xml version="1.0"?>
        \\<rss version="2.0">
        \\  <channel>
        \\    <title>Test</title>
        \\    <link>https://example.com</link>
        \\    <description>Test feed</description>
        \\  </channel>
        \\</rss>
    ;

    var parser = Parser.init(allocator);
    const feed_type = try parser.detectFeedType(rss_xml);
    try std.testing.expect(feed_type == .rss);
}

test "detect Atom feed" {
    const allocator = std.testing.allocator;

    const atom_xml =
        \\<?xml version="1.0"?>
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <id>test</id>
        \\  <title>Test</title>
        \\  <updated>2024-01-01T00:00:00Z</updated>
        \\</feed>
    ;

    var parser = Parser.init(allocator);
    const feed_type = try parser.detectFeedType(atom_xml);
    try std.testing.expect(feed_type == .atom);
}

test "detect JSON Feed" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{
        \\  "version": "https://jsonfeed.org/version/1.1",
        \\  "title": "Test"
        \\}
    ;

    var parser = Parser.init(allocator);
    const feed_type = try parser.detectFeedType(json_data);
    try std.testing.expect(feed_type == .json_feed);
}

test "parse RSS feed via unified parser" {
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
        \\      <description>Content here</description>
        \\      <guid>post-1</guid>
        \\    </item>
        \\  </channel>
        \\</rss>
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(rss_xml);
    defer feed.deinit();

    try std.testing.expect(feed.feed_type == .rss);
    try std.testing.expectEqualStrings("Tech Blog", feed.title);
    try std.testing.expectEqualStrings("https://techblog.com", feed.url.?);
    try std.testing.expect(feed.items.items.len == 1);
    try std.testing.expectEqualStrings("First Post", feed.items.items[0].title.?);
}

test "parse Atom feed via unified parser" {
    const allocator = std.testing.allocator;

    const atom_xml =
        \\<?xml version="1.0"?>
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <id>urn:uuid:test</id>
        \\  <title>My Blog</title>
        \\  <updated>2024-01-01T00:00:00Z</updated>
        \\  <entry>
        \\    <id>urn:uuid:entry-1</id>
        \\    <title>First Entry</title>
        \\    <updated>2024-01-01T00:00:00Z</updated>
        \\    <content>Entry content</content>
        \\  </entry>
        \\</feed>
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(atom_xml);
    defer feed.deinit();

    try std.testing.expect(feed.feed_type == .atom);
    try std.testing.expectEqualStrings("My Blog", feed.title);
    try std.testing.expect(feed.items.items.len == 1);
    try std.testing.expectEqualStrings("First Entry", feed.items.items[0].title.?);
}

test "parse JSON Feed via unified parser" {
    const allocator = std.testing.allocator;

    const json_data =
        \\{
        \\  "version": "https://jsonfeed.org/version/1.1",
        \\  "title": "My Feed",
        \\  "home_page_url": "https://example.com",
        \\  "items": [
        \\    {
        \\      "id": "1",
        \\      "title": "First Item",
        \\      "content_text": "Item content"
        \\    }
        \\  ]
        \\}
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(json_data);
    defer feed.deinit();

    try std.testing.expect(feed.feed_type == .json_feed);
    try std.testing.expectEqualStrings("My Feed", feed.title);
    try std.testing.expectEqualStrings("https://example.com", feed.url.?);
    try std.testing.expect(feed.items.items.len == 1);
    try std.testing.expectEqualStrings("First Item", feed.items.items[0].title.?);
}

test "error on unknown format" {
    const allocator = std.testing.allocator;

    const invalid = "<html><body>Not a feed</body></html>";

    var parser = Parser.init(allocator);
    try std.testing.expectError(FeedError.UnknownFeedFormat, parser.parse(invalid));
}
