const std = @import("std");
const Allocator = std.mem.Allocator;

pub const JsonFeedError = error{
    InvalidJsonFeed,
    MissingRequiredField,
    OutOfMemory,
    ParseError,
};

pub const JsonFeedAttachment = struct {
    url: []const u8,
    mime_type: []const u8,
    title: ?[]const u8 = null,
    size_in_bytes: ?u64 = null,
};

pub const JsonFeedAuthor = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    avatar: ?[]const u8 = null,
};

pub const JsonFeedItem = struct {
    id: []const u8,
    url: ?[]const u8 = null,
    external_url: ?[]const u8 = null,
    title: ?[]const u8 = null,
    content_html: ?[]const u8 = null,
    content_text: ?[]const u8 = null,
    summary: ?[]const u8 = null,
    image: ?[]const u8 = null,
    banner_image: ?[]const u8 = null,
    date_published: ?[]const u8 = null,
    date_modified: ?[]const u8 = null,
    authors: std.ArrayList(JsonFeedAuthor),
    tags: std.ArrayList([]const u8),
    attachments: std.ArrayList(JsonFeedAttachment),

    pub fn deinit(self: *JsonFeedItem, allocator: Allocator) void {
        self.authors.deinit(allocator);
        self.tags.deinit(allocator);
        self.attachments.deinit(allocator);
    }
};

pub const JsonFeed = struct {
    version: []const u8,
    title: []const u8,
    home_page_url: ?[]const u8 = null,
    feed_url: ?[]const u8 = null,
    description: ?[]const u8 = null,
    icon: ?[]const u8 = null,
    favicon: ?[]const u8 = null,
    authors: std.ArrayList(JsonFeedAuthor),
    language: ?[]const u8 = null,
    items: std.ArrayList(JsonFeedItem),
    allocator: Allocator,
    parsed_json: std.json.Parsed(std.json.Value),

    pub fn deinit(self: *JsonFeed) void {
        self.authors.deinit(self.allocator);
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
        self.parsed_json.deinit();
    }
};

pub const Parser = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) Parser {
        return .{ .allocator = allocator };
    }

    pub fn parse(self: *Parser, input: []const u8) !JsonFeed {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, input, .{}) catch {
            return JsonFeedError.ParseError;
        };
        errdefer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return JsonFeedError.InvalidJsonFeed;

        return try self.parseJsonFeed(root.object, parsed);
    }

    fn parseJsonFeed(self: *Parser, obj: std.json.ObjectMap, parsed: std.json.Parsed(std.json.Value)) !JsonFeed {
        const version = self.getStringField(obj, "version") orelse return JsonFeedError.MissingRequiredField;
        const title = self.getStringField(obj, "title") orelse return JsonFeedError.MissingRequiredField;

        if (!std.mem.startsWith(u8, version, "https://jsonfeed.org/version/")) {
            return JsonFeedError.InvalidJsonFeed;
        }

        var authors = std.ArrayList(JsonFeedAuthor){};
        if (obj.get("authors")) |authors_value| {
            if (authors_value == .array) {
                for (authors_value.array.items) |author_value| {
                    if (author_value == .object) {
                        const author = try self.parseAuthor(author_value.object);
                        try authors.append(self.allocator, author);
                    }
                }
            }
        }

        var items = std.ArrayList(JsonFeedItem){};
        if (obj.get("items")) |items_value| {
            if (items_value == .array) {
                for (items_value.array.items) |item_value| {
                    if (item_value == .object) {
                        const item = try self.parseItem(item_value.object);
                        try items.append(self.allocator, item);
                    }
                }
            }
        }

        return JsonFeed{
            .version = version,
            .title = title,
            .home_page_url = self.getStringField(obj, "home_page_url"),
            .feed_url = self.getStringField(obj, "feed_url"),
            .description = self.getStringField(obj, "description"),
            .icon = self.getStringField(obj, "icon"),
            .favicon = self.getStringField(obj, "favicon"),
            .language = self.getStringField(obj, "language"),
            .authors = authors,
            .items = items,
            .allocator = self.allocator,
            .parsed_json = parsed,
        };
    }

    fn parseItem(self: *Parser, obj: std.json.ObjectMap) !JsonFeedItem {
        const id = self.getStringField(obj, "id") orelse return JsonFeedError.MissingRequiredField;

        var authors = std.ArrayList(JsonFeedAuthor){};
        if (obj.get("authors")) |authors_value| {
            if (authors_value == .array) {
                for (authors_value.array.items) |author_value| {
                    if (author_value == .object) {
                        const author = try self.parseAuthor(author_value.object);
                        try authors.append(self.allocator, author);
                    }
                }
            }
        }

        var tags = std.ArrayList([]const u8){};
        if (obj.get("tags")) |tags_value| {
            if (tags_value == .array) {
                for (tags_value.array.items) |tag_value| {
                    if (tag_value == .string) {
                        try tags.append(self.allocator, tag_value.string);
                    }
                }
            }
        }

        var attachments = std.ArrayList(JsonFeedAttachment){};
        if (obj.get("attachments")) |attachments_value| {
            if (attachments_value == .array) {
                for (attachments_value.array.items) |attachment_value| {
                    if (attachment_value == .object) {
                        const attachment = try self.parseAttachment(attachment_value.object);
                        try attachments.append(self.allocator, attachment);
                    }
                }
            }
        }

        return JsonFeedItem{
            .id = id,
            .url = self.getStringField(obj, "url"),
            .external_url = self.getStringField(obj, "external_url"),
            .title = self.getStringField(obj, "title"),
            .content_html = self.getStringField(obj, "content_html"),
            .content_text = self.getStringField(obj, "content_text"),
            .summary = self.getStringField(obj, "summary"),
            .image = self.getStringField(obj, "image"),
            .banner_image = self.getStringField(obj, "banner_image"),
            .date_published = self.getStringField(obj, "date_published"),
            .date_modified = self.getStringField(obj, "date_modified"),
            .authors = authors,
            .tags = tags,
            .attachments = attachments,
        };
    }

    fn parseAuthor(self: *Parser, obj: std.json.ObjectMap) !JsonFeedAuthor {
        _ = self;
        return JsonFeedAuthor{
            .name = if (obj.get("name")) |v| if (v == .string) v.string else null else null,
            .url = if (obj.get("url")) |v| if (v == .string) v.string else null else null,
            .avatar = if (obj.get("avatar")) |v| if (v == .string) v.string else null else null,
        };
    }

    fn parseAttachment(self: *Parser, obj: std.json.ObjectMap) !JsonFeedAttachment {
        const url = self.getStringField(obj, "url") orelse return JsonFeedError.MissingRequiredField;
        const mime_type = self.getStringField(obj, "mime_type") orelse return JsonFeedError.MissingRequiredField;

        var size: ?u64 = null;
        if (obj.get("size_in_bytes")) |size_value| {
            if (size_value == .integer) {
                size = @intCast(size_value.integer);
            }
        }

        return JsonFeedAttachment{
            .url = url,
            .mime_type = mime_type,
            .title = self.getStringField(obj, "title"),
            .size_in_bytes = size,
        };
    }

    fn getStringField(self: *Parser, obj: std.json.ObjectMap, field: []const u8) ?[]const u8 {
        _ = self;
        if (obj.get(field)) |value| {
            if (value == .string) {
                return value.string;
            }
        }
        return null;
    }
};

// Tests
test "parse minimal JSON Feed" {
    const allocator = std.testing.allocator;

    const json_feed =
        \\{
        \\  "version": "https://jsonfeed.org/version/1.1",
        \\  "title": "My Test Feed"
        \\}
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(json_feed);
    defer feed.deinit();

    try std.testing.expectEqualStrings("https://jsonfeed.org/version/1.1", feed.version);
    try std.testing.expectEqualStrings("My Test Feed", feed.title);
}

test "parse JSON Feed with items" {
    const allocator = std.testing.allocator;

    const json_feed =
        \\{
        \\  "version": "https://jsonfeed.org/version/1.1",
        \\  "title": "My Blog",
        \\  "home_page_url": "https://example.com/",
        \\  "items": [
        \\    {
        \\      "id": "1",
        \\      "url": "https://example.com/post-1",
        \\      "title": "First Post",
        \\      "content_html": "<p>Hello, world!</p>",
        \\      "date_published": "2024-01-01T00:00:00Z"
        \\    },
        \\    {
        \\      "id": "2",
        \\      "url": "https://example.com/post-2",
        \\      "title": "Second Post",
        \\      "content_text": "Hello again!"
        \\    }
        \\  ]
        \\}
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(json_feed);
    defer feed.deinit();

    try std.testing.expectEqualStrings("My Blog", feed.title);
    try std.testing.expectEqualStrings("https://example.com/", feed.home_page_url.?);
    try std.testing.expect(feed.items.items.len == 2);

    const item1 = feed.items.items[0];
    try std.testing.expectEqualStrings("1", item1.id);
    try std.testing.expectEqualStrings("First Post", item1.title.?);
    try std.testing.expectEqualStrings("<p>Hello, world!</p>", item1.content_html.?);
    try std.testing.expectEqualStrings("2024-01-01T00:00:00Z", item1.date_published.?);

    const item2 = feed.items.items[1];
    try std.testing.expectEqualStrings("2", item2.id);
    try std.testing.expectEqualStrings("Hello again!", item2.content_text.?);
}

test "parse JSON Feed with authors" {
    const allocator = std.testing.allocator;

    const json_feed =
        \\{
        \\  "version": "https://jsonfeed.org/version/1.1",
        \\  "title": "My Blog",
        \\  "authors": [
        \\    {
        \\      "name": "Jane Doe",
        \\      "url": "https://janedoe.com",
        \\      "avatar": "https://janedoe.com/avatar.jpg"
        \\    }
        \\  ],
        \\  "items": [
        \\    {
        \\      "id": "1",
        \\      "title": "Post",
        \\      "authors": [
        \\        {
        \\          "name": "John Smith"
        \\        }
        \\      ]
        \\    }
        \\  ]
        \\}
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(json_feed);
    defer feed.deinit();

    try std.testing.expect(feed.authors.items.len == 1);
    const feed_author = feed.authors.items[0];
    try std.testing.expectEqualStrings("Jane Doe", feed_author.name.?);
    try std.testing.expectEqualStrings("https://janedoe.com", feed_author.url.?);
    try std.testing.expectEqualStrings("https://janedoe.com/avatar.jpg", feed_author.avatar.?);

    try std.testing.expect(feed.items.items.len == 1);
    const item = feed.items.items[0];
    try std.testing.expect(item.authors.items.len == 1);
    try std.testing.expectEqualStrings("John Smith", item.authors.items[0].name.?);
}

test "parse JSON Feed with tags and attachments" {
    const allocator = std.testing.allocator;

    const json_feed =
        \\{
        \\  "version": "https://jsonfeed.org/version/1.1",
        \\  "title": "Podcast",
        \\  "items": [
        \\    {
        \\      "id": "ep1",
        \\      "title": "Episode 1",
        \\      "tags": ["technology", "programming"],
        \\      "attachments": [
        \\        {
        \\          "url": "https://example.com/ep1.mp3",
        \\          "mime_type": "audio/mpeg",
        \\          "title": "Episode 1 Audio",
        \\          "size_in_bytes": 12345678
        \\        }
        \\      ]
        \\    }
        \\  ]
        \\}
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(json_feed);
    defer feed.deinit();

    try std.testing.expect(feed.items.items.len == 1);
    const item = feed.items.items[0];
    
    try std.testing.expect(item.tags.items.len == 2);
    try std.testing.expectEqualStrings("technology", item.tags.items[0]);
    try std.testing.expectEqualStrings("programming", item.tags.items[1]);

    try std.testing.expect(item.attachments.items.len == 1);
    const attachment = item.attachments.items[0];
    try std.testing.expectEqualStrings("https://example.com/ep1.mp3", attachment.url);
    try std.testing.expectEqualStrings("audio/mpeg", attachment.mime_type);
    try std.testing.expectEqualStrings("Episode 1 Audio", attachment.title.?);
    try std.testing.expect(attachment.size_in_bytes.? == 12345678);
}

test "parse JSON Feed with optional feed fields" {
    const allocator = std.testing.allocator;

    const json_feed =
        \\{
        \\  "version": "https://jsonfeed.org/version/1.1",
        \\  "title": "My Feed",
        \\  "home_page_url": "https://example.com/",
        \\  "feed_url": "https://example.com/feed.json",
        \\  "description": "A test feed",
        \\  "icon": "https://example.com/icon.png",
        \\  "favicon": "https://example.com/favicon.ico",
        \\  "language": "en-US"
        \\}
    ;

    var parser = Parser.init(allocator);
    var feed = try parser.parse(json_feed);
    defer feed.deinit();

    try std.testing.expectEqualStrings("https://example.com/", feed.home_page_url.?);
    try std.testing.expectEqualStrings("https://example.com/feed.json", feed.feed_url.?);
    try std.testing.expectEqualStrings("A test feed", feed.description.?);
    try std.testing.expectEqualStrings("https://example.com/icon.png", feed.icon.?);
    try std.testing.expectEqualStrings("https://example.com/favicon.ico", feed.favicon.?);
    try std.testing.expectEqualStrings("en-US", feed.language.?);
}

test "error on invalid JSON" {
    const allocator = std.testing.allocator;

    const invalid_json = "{ invalid json }";

    var parser = Parser.init(allocator);
    try std.testing.expectError(JsonFeedError.ParseError, parser.parse(invalid_json));
}

test "error on missing required fields" {
    const allocator = std.testing.allocator;

    const incomplete_json =
        \\{
        \\  "version": "https://jsonfeed.org/version/1.1"
        \\}
    ;

    var parser = Parser.init(allocator);
    try std.testing.expectError(JsonFeedError.MissingRequiredField, parser.parse(incomplete_json));
}

test "error on invalid version" {
    const allocator = std.testing.allocator;

    const invalid_version =
        \\{
        \\  "version": "1.0",
        \\  "title": "My Feed"
        \\}
    ;

    var parser = Parser.init(allocator);
    try std.testing.expectError(JsonFeedError.InvalidJsonFeed, parser.parse(invalid_version));
}
