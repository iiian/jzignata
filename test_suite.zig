const std = @import("std");
const Jz = @import("jsonata.zig");
const json = std.json;
const fs = std.fs;
const mem = std.mem;
const path = fs.path;

const print = std.debug.print;
const expect = std.testing.expect;

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

    var tc = json.parseFromSlice(TestCase, m, tcraw, json.ParseOptions{
      .ignore_unknown_fields = true,
    }) catch continue;
    defer tc.deinit();
    const dsfname = try std.mem.concat(m, u8, &.{ tc.value.dataset, ".json" });
    const dspath = try path.join(m, &(frag_chunk ++ .{ "datasets", dsfname }));
    const dsraw = try std.fs.cwd().readFileAlloc(m, dspath, std.math.maxInt(usize));
    _ = dsraw;
    var expected = std.ArrayList(u8).init(m);
    defer expected.deinit();
    var actual = std.ArrayList(u8).init(m);
    defer actual.deinit();
    const expr: Jz.Expr = try Jz.jsonata(tc.value.expr);
    try json.stringify(try expr.evaluate(), .{}, actual.writer());
    try json.stringify(tc.value.result, .{}, expected.writer());

    if (!std.mem.eql(u8, expected.items, actual.items)) {
      print("[!!] TESTCASE: {s}{s}\n", .{entry.path, dsfname});
      print("     DATASET: {s}\n", .{tc.value.dataset});
      print("     expr: {s}\n", .{tc.value.expr});
      print("     expected: {s}\n", .{expected.items});
      print("     got: {d}\n", .{actual.items});
      try std.testing.expectEqualSlices(u8, expected.items, actual.items);
      // try expect(std.mem.eql(u8, expected.items, actual.items));
    } else {
      print("[OK] TESTCASE: {s}\n", .{dsfname});
    }
    print("\n", .{});
  }
}
