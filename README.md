# What's Updog?

Nothin' much, how about you?

Updog is a zig-based feed parsing library. Updog supports parsing RSS feeds, Atom feeds, and JSON feeds (YUCK).

### Features

#### **XML Parser** - Full-featured XML 1.0 parser

The XML Parser is the backbone of the RSS and Atom parsers.


#### **RSS Parser** - RSS 2.0 support
- Channel metadata (title, link, description, etc.)
- Feed items with all standard fields
- Enclosure support for podcasts
- Optional fields (language, copyright, etc.)

#### **Atom Parser** - Atom 1.0 support
- Feed and entry metadata
- Links with rel/type attributes
- Author information
- Categories

#### **JSON Feed Parser** - JSON Feed 1.0/1.1 support
- Feed metadata
- Items with authors, tags, attachments

#### **Unified Feed Parser** - Automatic format detection
- As a consumer, you probably want to use this.
- Detects RSS, Atom, and JSON Feed formats automatically
- Provides common interface across all formats
- Normalizes all feeds to unified structure

## Project Structure

```
src/
├── xml/
│   ├── parser.zig       # XML parser implementation
│   ├── example.zig      # XML usage example
│   └── README.md        # XML parser documentation
│
└── feeds/
    ├── rss/
    │   └── parser.zig   # RSS 2.0 parser
    ├── atom/
    │   └── parser.zig   # Atom 1.0 parser
    ├── json/
    │   └── parser.zig   # JSON Feed parser
    └── README.md        # Feed parsers documentation
```

## Building and Testing

### Build Configuration

The `build.zig` is configured with modules for each parser:

- `xml` - XML parser module
- `rss` - RSS parser module (depends on xml)
- `atom` - Atom parser module (depends on xml)  
- `json_feed` - JSON Feed parser module
- `feed_parser` - Unified feed parser (depends on all parsers)

### Running Tests

All tests:
```bash
zig build test
```

Individual parser tests:
```bash
zig build test-xml       # 11 tests
zig build test-rss       # 6 tests
zig build test-atom      # 7 tests
zig build test-json      # 8 tests
zig build test-feed      # 7 tests (unified parser)
```

Run examples:
```bash
zig build run-feed-example  # Unified parser demo
```

## Usage

### In Your Project

Add to your `build.zig.zon`:
```zig
.dependencies = .{
    .updog = .{
        .path = "path/to/updog",
    },
},
```

Import parsers in your code:
```zig
const xml = @import("xml");
const rss = @import("rss");
const atom = @import("atom");
const json_feed = @import("json_feed");
const feed_parser = @import("feed_parser");  // Unified parser
```

### Example: Unified Feed Parser (Recommended)

The unified parser automatically detects the feed format and provides a common interface:

```zig
const std = @import("std");
const feed_parser = @import("feed_parser");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read any feed format (RSS, Atom, or JSON Feed)
    const feed_data = try std.fs.cwd().readFileAlloc(
        allocator,
        "feed.xml",  // or feed.json
        10 * 1024 * 1024,
    );
    defer allocator.free(feed_data);

    // Parse automatically detects format
    var parser = feed_parser.Parser.init(allocator);
    var feed = try parser.parse(feed_data);
    defer feed.deinit();

    // Access unified feed structure
    std.debug.print("Format: {s}\n", .{@tagName(feed.feed_type)});
    std.debug.print("Title: {s}\n", .{feed.title});
    
    if (feed.url) |url| {
        std.debug.print("URL: {s}\n", .{url});
    }
    
    // All items have the same structure regardless of format
    for (feed.items.items) |item| {
        if (item.title) |title| {
            std.debug.print("\n{s}\n", .{title});
        }
        if (item.url) |url| {
            std.debug.print("  {s}\n", .{url});
        }
        if (item.author) |author| {
            std.debug.print("  By: {s}\n", .{author});
        }
    }
}
```

### Example: Parse an RSS Feed

```zig
const std = @import("std");
const rss = @import("rss");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read feed data
    const feed_data = try std.fs.cwd().readFileAlloc(
        allocator,
        "feed.xml",
        10 * 1024 * 1024, // 10MB max
    );
    defer allocator.free(feed_data);

    // Parse RSS feed
    var parser = rss.Parser.init(allocator);
    var feed = try parser.parse(feed_data);
    defer feed.deinit();

    // Access feed data
    std.debug.print("Channel: {s}\n", .{feed.channel.title});
    std.debug.print("Link: {s}\n", .{feed.channel.link});
    std.debug.print("Description: {s}\n", .{feed.channel.description});
    
    // Iterate over items
    for (feed.channel.items.items) |item| {
        if (item.title) |title| {
            std.debug.print("\nItem: {s}\n", .{title});
        }
        if (item.link) |link| {
            std.debug.print("  URL: {s}\n", .{link});
        }
        if (item.pub_date) |date| {
            std.debug.print("  Published: {s}\n", .{date});
        }
    }
}
```

### Example: Parse an Atom Feed

```zig
const atom = @import("atom");

var parser = atom.Parser.init(allocator);
var feed = try parser.parse(atom_data);
defer feed.deinit();

std.debug.print("Feed: {s}\n", .{feed.title});
for (feed.entries.items) |entry| {
    std.debug.print("  - {s}\n", .{entry.title});
    for (entry.links.items) |link| {
        std.debug.print("    Link: {s}\n", .{link.href});
    }
}
```

### Example: Parse a JSON Feed

```zig
const json_feed = @import("json_feed");

var parser = json_feed.Parser.init(allocator);
var feed = try parser.parse(json_data);
defer feed.deinit();

std.debug.print("Feed: {s}\n", .{feed.title});
for (feed.items.items) |item| {
    if (item.title) |title| {
        std.debug.print("  - {s}\n", .{title});
    }
}
```

## API Reference

### Unified Feed Parser (Recommended)

**Types:**
- `Feed` - Normalized feed structure (all formats)
- `FeedItem` - Normalized item structure
- `FeedType` - Enum: `.rss`, `.atom`, `.json_feed`
- `FeedError` - Error types

**Unified Feed Structure:**
```zig
pub const Feed = struct {
    feed_type: FeedType,              // Detected format
    title: []const u8,                // Feed title
    url: ?[]const u8,                 // Feed URL
    description: ?[]const u8,         // Feed description
    items: std.ArrayList(FeedItem),   // Feed entries
    // ... internal storage for original feeds
}
```

**Unified Item Structure:**
```zig
pub const FeedItem = struct {
    id: ?[]const u8,              // Unique identifier
    title: ?[]const u8,           // Item title
    url: ?[]const u8,             // Item URL
    content_html: ?[]const u8,    // HTML content
    content_text: ?[]const u8,    // Plain text content
    summary: ?[]const u8,         // Summary/description
    date_published: ?[]const u8,  // Publication date
    date_modified: ?[]const u8,   // Last modified date
    author: ?[]const u8,          // Author name
    tags: std.ArrayList([]const u8), // Tags/categories
}
```

**Usage:**
```zig
var parser = feed_parser.Parser.init(allocator);
var feed = try parser.parse(feed_data);
defer feed.deinit();

// Feed type is automatically detected
switch (feed.feed_type) {
    .rss => std.debug.print("RSS feed\n", .{}),
    .atom => std.debug.print("Atom feed\n", .{}),
    .json_feed => std.debug.print("JSON Feed\n", .{}),
}
```

### RSS Parser

**Types:**
- `RssFeed` - Top-level feed structure
- `RssChannel` - Channel metadata and items
- `RssItem` - Individual feed entry
- `RssError` - Error types

**Required Channel Fields:**
- title, link, description

**Optional Channel Fields:**
- language, copyright, managingEditor, webMaster, pubDate, lastBuildDate, category, generator, ttl

**Item Fields:**
- title, link, description, author, category, comments, enclosure_url, enclosure_type, guid, pub_date, source

### Atom Parser

**Types:**
- `AtomFeed` - Top-level feed structure
- `AtomEntry` - Individual entry
- `AtomLink` - Link with href/rel/type
- `AtomPerson` - Author/contributor info
- `AtomError` - Error types

**Required Feed Fields:**
- id, title, updated

**Optional Feed Fields:**
- subtitle, links, authors, entries

### JSON Feed Parser

**Types:**
- `JsonFeed` - Top-level feed structure
- `JsonFeedItem` - Individual item
- `JsonFeedAuthor` - Author information
- `JsonFeedAttachment` - Attached files (podcasts, etc.)
- `JsonFeedError` - Error types

**Required Feed Fields:**
- version, title

**Optional Feed Fields:**
- home_page_url, feed_url, description, icon, favicon, authors, language, items

## Development

### Adding New Features

1. Write tests (first, ideally)
2. Implement feature
3. Ensure all tests pass: `zig build test`
4. Update documentation

### Code Style

- Use Zig standard library conventions
- Minimize comments (code should be self-documenting)
- Proper memory management with allocators
- Use `errdefer` for cleanup on error paths

## Roadmap

- [x] XML parser
- [x] RSS 2.0 parser
- [x] Atom 1.0 parser
- [x] JSON Feed parser
- [x] Comprehensive test suites
- [x] Build system integration
- [x] **Unified feed detection and parsing**
- [ ] Real-world feed integration tests
- [ ] Feed autodiscovery from HTML
- [ ] Feed validation
- [ ] Performance benchmarks

## Contributing

Contributions welcome! Please ensure:
1. All tests pass
2. New features include tests
3. Code follows project conventions
