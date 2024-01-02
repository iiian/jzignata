const Value = @import("std").json.Value;

pub fn jsonata(expr: []const u8) !Value {
  _ = expr;
  return Value{
    .bool = true
  };
}