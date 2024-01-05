const std = @import("std");
const Value = @import("std").json.Value;
const Parser = @import("parser.zig").Parser;
const Tokenizer = @import("parser.zig").Tokenizer;
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
    // TODO: required? precisely avoided? how to mem-manage?
    // defer _ = gpa.deinit();
    var parser = Parser.init(allocator, expr);
    const ast = try parser.parse();
    _ = ast;
    return .{};
}

pub fn main() !void {
    const haystack = "$$.x&$$.y";
    var alloc = std.heap.GeneralPurposeAllocator(.{}){};
    var lexer = Tokenizer.init(alloc.allocator(), haystack);
    while (try lexer.next(false)) |tok| {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}\n", .{tok.val});
    }
}
