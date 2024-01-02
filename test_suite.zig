const std = @import("std");
const jsonata = @import("lib.zig").jsonata;
const json = std.json;
const fs = std.fs;
const mem = std.mem;
const path = fs.path;

const print = std.debug.print;

const TestCase = struct {
    expr: []u8,
    dataset: []u8,
    result: json.Value,
};

test "jsonata test suite" {
    var M = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer M.deinit();
    var m = M.allocator();

    const root = try fs.cwd().realpathAlloc(m, ".");
    defer m.free(root);
    const frag_chunk = .{ root, "test", "test-suite" };
    const groups = try path.join(m, &(frag_chunk ++ .{"groups"}));
    defer m.free(groups);
    var dir = try fs.openDirAbsolute(groups, .{});
    var subdirs = try dir.walk(m);
    defer subdirs.deinit();
    while (try subdirs.next()) |entry| {
        if (!(std.mem.startsWith(u8, entry.basename, "case") and
            std.mem.endsWith(u8, entry.basename, ".json"))) continue;

        // test case spec
        const tcpath = try path.join(m, &.{ groups, entry.path });
        const tcraw = try std.fs.cwd().readFileAlloc(m, tcpath, std.math.maxInt(usize));
        defer m.free(tcraw);

        const tc = json.parseFromSlice(TestCase, m, tcraw, json.ParseOptions{
            .ignore_unknown_fields = true,
        }) catch continue;
        defer tc.deinit();
        const dsfname = try std.mem.concat(m, u8, &.{ tc.value.dataset, ".json" });
        const dspath = try path.join(m, &(frag_chunk ++ .{ "datasets", dsfname }));
        const dsraw = try std.fs.cwd().readFileAlloc(m, dspath, std.math.maxInt(usize));
        print("{s}\n", .{tcpath});
        print("{s}\n", .{tc.value.expr});
        print("{d}\n", .{dsraw.len});
        tc.value.result.dump();
        print("\n\n", .{});
    }
}

test "final" {
    _ = try jsonata("Foo fuz");
}