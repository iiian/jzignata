const std = @import("std");
const Value = @import("std").json.Value;
const parser = @import("parser.zig");
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
  const ast = try parser.Parser.parse(expr);
  _ = ast;
  return .{};
}