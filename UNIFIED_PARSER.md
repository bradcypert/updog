## Format Detection

The parser examines the input to determine format:

1. **JSON Feed**: Starts with `{`
2. **RSS**: Contains `<rss` root element
3. **Atom**: Contains `<feed` root element

XML declarations are automatically skipped. Unknown formats return `FeedError.UnknownFeedFormat`.

## Field Mapping

How fields from different formats map to the unified structure:

| Unified Field | RSS | Atom | JSON Feed |
|--------------|-----|------|-----------|
| `title` | `channel/title` | `feed/title` | `title` |
| `url` | `channel/link` | `feed/link[@rel=alternate]` | `home_page_url` |
| `description` | `channel/description` | `feed/subtitle` | `description` |
| `item.id` | `item/guid` | `entry/id` | `items[]/id` |
| `item.title` | `item/title` | `entry/title` | `items[]/title` |
| `item.url` | `item/link` | `entry/link[@rel=alternate]` | `items[]/url` |
| `item.content_html` | `item/description` | `entry/content` | `items[]/content_html` |
| `item.content_text` | - | - | `items[]/content_text` |
| `item.summary` | - | `entry/summary` | `items[]/summary` |
| `item.date_published` | `item/pubDate` | `entry/published` | `items[]/date_published` |
| `item.date_modified` | - | `entry/updated` | `items[]/date_modified` |
| `item.author` | `item/author` | `entry/author/name` | `items[]/authors[0]/name` |
| `item.tags` | `item/category` | `entry/category[@term]` | `items[]/tags` |

## Error Handling

```zig
const result = parser.parse(data);
result catch |err| switch (err) {
    FeedError.UnknownFeedFormat => {
        // Not RSS, Atom, or JSON Feed
    },
    FeedError.InvalidFeed => {
        // Malformed feed structure
    },
    FeedError.OutOfMemory => {
        // Allocation failed
    },
    else => {
        // Other errors from underlying parsers
    },
};
```

## Examples

See `src/feeds/example.zig` for a complete working example that demonstrates:
- Parsing RSS feeds
- Parsing Atom feeds
- Parsing JSON Feeds
- Accessing unified feed structures
- Iterating over items

Run it with:
```bash
zig build run-feed-example
```

## Testing

Run unified parser tests:
```bash
zig build test-feed
```

This runs 7 tests covering:
- Format detection for RSS, Atom, and JSON
- Full parsing of each format
- Error handling for unknown formats
- Unified data structure verification

## Performance

The unified parser adds minimal overhead:
- Format detection is O(n) where n is the prefix length
- No extra allocations beyond format-specific parsers
- Memory is efficiently managed with proper cleanup

## Integration

The unified parser is the recommended way to use the feed parsing library:

```zig
// In your build.zig
const feed_parser = b.dependency("updog", .{}).module("feed_parser");

// In your code
const feed_parser = @import("feed_parser");
```

All underlying parsers (XML, RSS, Atom, JSON Feed) are available as dependencies if you need format-specific features.
