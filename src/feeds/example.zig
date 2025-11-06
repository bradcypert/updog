const std = @import("std");
const feed_parser = @import("feed_parser");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Example feeds in different formats
    const rss_example =
        \\<?xml version="1.0"?>
        \\<rss version="2.0">
        \\  <channel>
        \\    <title>Tech News</title>
        \\    <link>https://technews.example.com</link>
        \\    <description>Latest in technology</description>
        \\    <item>
        \\      <title>Zig 0.15 Released</title>
        \\      <link>https://technews.example.com/zig-0-15</link>
        \\      <description>New features in Zig 0.15</description>
        \\      <pubDate>Mon, 01 Jan 2024 12:00:00 GMT</pubDate>
        \\      <guid>zig-0-15</guid>
        \\    </item>
        \\    <item>
        \\      <title>Understanding Allocators</title>
        \\      <link>https://technews.example.com/allocators</link>
        \\      <description>Deep dive into memory management</description>
        \\      <pubDate>Sun, 31 Dec 2023 10:00:00 GMT</pubDate>
        \\    </item>
        \\  </channel>
        \\</rss>
    ;

    const atom_example =
        \\<?xml version="1.0"?>
        \\<feed xmlns="http://www.w3.org/2005/Atom">
        \\  <id>urn:uuid:12345</id>
        \\  <title>Developer Blog</title>
        \\  <updated>2024-01-01T12:00:00Z</updated>
        \\  <link href="https://devblog.example.com" rel="alternate"/>
        \\  <entry>
        \\    <id>urn:uuid:entry-1</id>
        \\    <title>Building with Zig</title>
        \\    <updated>2024-01-01T12:00:00Z</updated>
        \\    <link href="https://devblog.example.com/building-with-zig" rel="alternate"/>
        \\    <content>Tutorial on building applications with Zig...</content>
        \\    <author>
        \\      <name>Jane Developer</name>
        \\    </author>
        \\    <category term="programming"/>
        \\    <category term="zig"/>
        \\  </entry>
        \\</feed>
    ;

    const json_example =
        \\{
        \\  "version": "https://jsonfeed.org/version/1.1",
        \\  "title": "Podcast Feed",
        \\  "home_page_url": "https://podcast.example.com",
        \\  "description": "Weekly tech podcast",
        \\  "items": [
        \\    {
        \\      "id": "episode-42",
        \\      "title": "Episode 42: The Answer",
        \\      "url": "https://podcast.example.com/episode-42",
        \\      "content_text": "In this episode we discuss...",
        \\      "date_published": "2024-01-01T12:00:00Z",
        \\      "authors": [
        \\        {"name": "John Host"}
        \\      ],
        \\      "tags": ["tech", "programming"],
        \\      "attachments": [
        \\        {
        \\          "url": "https://podcast.example.com/ep42.mp3",
        \\          "mime_type": "audio/mpeg",
        \\          "title": "Episode 42 Audio"
        \\        }
        \\      ]
        \\    }
        \\  ]
        \\}
    ;

    std.debug.print("=== Unified Feed Parser Example ===\n\n", .{});

    // Parse RSS feed
    std.debug.print("--- RSS Feed ---\n", .{});
    {
        var parser = feed_parser.Parser.init(allocator);
        var feed = try parser.parse(rss_example);
        defer feed.deinit();

        printFeed(&feed);
    }

    // Parse Atom feed
    std.debug.print("\n--- Atom Feed ---\n", .{});
    {
        var parser = feed_parser.Parser.init(allocator);
        var feed = try parser.parse(atom_example);
        defer feed.deinit();

        printFeed(&feed);
    }

    // Parse JSON Feed
    std.debug.print("\n--- JSON Feed ---\n", .{});
    {
        var parser = feed_parser.Parser.init(allocator);
        var feed = try parser.parse(json_example);
        defer feed.deinit();

        printFeed(&feed);
    }
}

fn printFeed(feed: *const feed_parser.Feed) void {
    std.debug.print("Type: {s}\n", .{@tagName(feed.feed_type)});
    std.debug.print("Title: {s}\n", .{feed.title});

    if (feed.url) |url| {
        std.debug.print("URL: {s}\n", .{url});
    }

    if (feed.description) |desc| {
        std.debug.print("Description: {s}\n", .{desc});
    }

    std.debug.print("Items: {d}\n", .{feed.items.items.len});

    for (feed.items.items, 0..) |item, i| {
        std.debug.print("\n  [{d}] ", .{i + 1});

        if (item.title) |title| {
            std.debug.print("{s}\n", .{title});
        } else {
            std.debug.print("(no title)\n", .{});
        }

        if (item.url) |url| {
            std.debug.print("      URL: {s}\n", .{url});
        }

        if (item.author) |author| {
            std.debug.print("      Author: {s}\n", .{author});
        }

        if (item.date_published) |date| {
            std.debug.print("      Published: {s}\n", .{date});
        }

        if (item.tags.items.len > 0) {
            std.debug.print("      Tags: ", .{});
            for (item.tags.items, 0..) |tag, j| {
                if (j > 0) std.debug.print(", ", .{});
                std.debug.print("{s}", .{tag});
            }
            std.debug.print("\n", .{});
        }
    }
}
