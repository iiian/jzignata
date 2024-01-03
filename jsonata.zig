const std = @import("std");
const Value = @import("std").json.Value;
const Parser = @import("parser.zig").Parser;
const print = std.debug.print;

pub const Expr = struct {
  pub fn evaluate(self: *const @This()) !Value {
    _ = self;
    return Value{
      .bool = true,
    };
  }
  pub fn assign(self: *const @This()) void {
    _ = self;
  }
};

pub fn jsonata(expr: []const u8) !Expr {
  var gpa = std.heap.GeneralPurposeAllocator(.{}){};
  const allocator = gpa.allocator();
  defer _ = gpa.deinit();
  var parser = Parser.create(allocator, expr);
  const ast = try parser.parse();
  _ = ast;
  return .{};
}

pub fn main() !void {
  _ = try jsonata("hello world");
}