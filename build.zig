const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // Create XML parser module
    const xml_module = b.addModule("xml", .{
        .root_source_file = b.path("src/xml/parser.zig"),
        .target = target,
    });

    // Create RSS parser module (depends on xml)
    const rss_module = b.addModule("rss", .{
        .root_source_file = b.path("src/feeds/rss/parser.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "xml", .module = xml_module },
        },
    });

    // Create Atom parser module (depends on xml)
    const atom_module = b.addModule("atom", .{
        .root_source_file = b.path("src/feeds/atom/parser.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "xml", .module = xml_module },
        },
    });

    // Create JSON Feed parser module
    const json_feed_module = b.addModule("json_feed", .{
        .root_source_file = b.path("src/feeds/json/parser.zig"),
        .target = target,
    });

    // Create unified feed parser module (depends on all parsers)
    const feed_parser_module = b.addModule("feed_parser", .{
        .root_source_file = b.path("src/feeds/parser.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "xml", .module = xml_module },
            .{ .name = "rss", .module = rss_module },
            .{ .name = "atom", .module = atom_module },
            .{ .name = "json_feed", .module = json_feed_module },
        },
    });

    // Main updog module
    const mod = b.addModule("updog", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .imports = &.{
            .{ .name = "xml", .module = xml_module },
            .{ .name = "rss", .module = rss_module },
            .{ .name = "atom", .module = atom_module },
            .{ .name = "json_feed", .module = json_feed_module },
            .{ .name = "feed_parser", .module = feed_parser_module },
        },
    });

    // Feed parser example executable
    const feed_example = b.addExecutable(.{
        .name = "feed-example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/feeds/example.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "feed_parser", .module = feed_parser_module },
            },
        }),
    });
    b.installArtifact(feed_example);

    // Run step for feed example
    const run_feed_example_step = b.step("run-feed-example", "Run the feed parser example");
    const run_feed_example = b.addRunArtifact(feed_example);
    run_feed_example_step.dependOn(&run_feed_example.step);
    run_feed_example.step.dependOn(b.getInstallStep());

    // Main executable
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // business logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    const exe = b.addExecutable(.{
        .name = "updog",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "updog" is the name you will use in your source code to
                // import this module (e.g. `@import("updog")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "updog", .module = mod },
            },
        }),
    });

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Test executables for each module
    const xml_tests = b.addTest(.{
        .root_module = xml_module,
    });
    const run_xml_tests = b.addRunArtifact(xml_tests);

    const rss_tests = b.addTest(.{
        .root_module = rss_module,
    });
    const run_rss_tests = b.addRunArtifact(rss_tests);

    const atom_tests = b.addTest(.{
        .root_module = atom_module,
    });
    const run_atom_tests = b.addRunArtifact(atom_tests);

    const json_feed_tests = b.addTest(.{
        .root_module = json_feed_module,
    });
    const run_json_feed_tests = b.addRunArtifact(json_feed_tests);

    const feed_parser_tests = b.addTest(.{
        .root_module = feed_parser_module,
    });
    const run_feed_parser_tests = b.addRunArtifact(feed_parser_tests);

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // Test step that runs all tests
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_xml_tests.step);
    test_step.dependOn(&run_rss_tests.step);
    test_step.dependOn(&run_atom_tests.step);
    test_step.dependOn(&run_json_feed_tests.step);
    test_step.dependOn(&run_feed_parser_tests.step);
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);

    // Individual test steps for convenience
    const test_xml_step = b.step("test-xml", "Run XML parser tests");
    test_xml_step.dependOn(&run_xml_tests.step);

    const test_rss_step = b.step("test-rss", "Run RSS parser tests");
    test_rss_step.dependOn(&run_rss_tests.step);

    const test_atom_step = b.step("test-atom", "Run Atom parser tests");
    test_atom_step.dependOn(&run_atom_tests.step);

    const test_json_step = b.step("test-json", "Run JSON Feed parser tests");
    test_json_step.dependOn(&run_json_feed_tests.step);

    const test_feed_step = b.step("test-feed", "Run unified feed parser tests");
    test_feed_step.dependOn(&run_feed_parser_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
