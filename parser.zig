const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Regex = @import("regex").Regex;
const json = std.json;
const unicode = std.unicode;

// [str] -> #
const operators = std.ComptimeStringMap(u8, .{
    .{ ".", 75 },
    .{ "[", 80 },
    .{ "]", 0 },
    .{ "{", 70 },
    .{ "}", 0 },
    .{ "(", 80 },
    .{ ")", 0 },
    .{ ",", 0 },
    .{ "@", 80 },
    .{ "#", 80 },
    .{ ";", 80 },
    .{ ":", 80 },
    .{ "?", 20 },
    .{ "+", 50 },
    .{ "-", 50 },
    .{ "*", 60 },
    .{ "/", 60 },
    .{ "%", 60 },
    .{ "|", 20 },
    .{ "=", 40 },
    .{ "<", 40 },
    .{ ">", 40 },
    .{ "^", 40 },
    .{ "**", 60 },
    .{ "..", 20 },
    .{ ":=", 10 },
    .{ "!=", 40 },
    .{ "<=", 40 },
    .{ ">=", 40 },
    .{ "~>", 40 },
    .{ "and", 30 },
    .{ "or", 25 },
    .{ "in", 40 },
    .{ "&", 50 },
    .{ "!", 0 }, // not an operator, but needed as a stop character for name token
    .{ "~", 0 }, // not an operator, but needed as a stop character for name token
}){};

// [str] -> char
const escapes = std.ComptimeStringMap(u8, .{
    .{ "\"", '"' },
    .{ "\\", '\\' },
    .{ "/", '/' },
    .{ "b", 'b' },
    .{ "f", 'f' },
    .{ "n", 'n' },
    .{ "t", 't' },
    .{ "r", 'r' },
}){};

const ParseErr = error{
    Unimplemented, // X0000
    NumOutOfRange, // S0102
    UnsupportedEscapeSequence, // S0103
    QuotedPropertyNameUnclosed, // S0105
    CommentDoesntEnd, // S0106
    SyntaxErr, // S0201
    ParentCannotBeDerived, // S0217
};

const GetTokenFn = *const fn (ctx: *Token) ParseErr!?*Token;

const Token = struct {
    id: ?[]u8 = null,
    // ancestor: ?Token // -- this won't matter until we do processAST
    // tuple?
    // expressions?
    // steps?
    pos: u32,
    typ: []u8,
    val: []u8,

    nud: GetTokenFn = Token.defaultGetter,
    led: GetTokenFn = Token.defaultGetter,

    pub fn init(pos: u32, typ: []u8, val: []u8) Token {
        return Token{
            .pos = pos,
            .typ = typ,
            .val = val,
        };
    }

    fn defaultGetter(ctx: *Token) ParseErr!?*Token {
        _ = ctx;
        return null;
    }
};

const ErrCtx = struct {
    code: []const u8,
    pos: usize,
    value: ?[]u8 = null,
    token: ?[]u8 = null,
};

// TODO: after tokenization creates the Ast, how do we deinit
//       everything we created for tokenization that is now stale?

/// Tokenizer
///   takes in a raw jsonata expression string
///   yields "tokens" until the (end) token is reached.
const Tokenizer = struct {
    pos: usize = 0,
    hay: []const u8,
    err: ?ErrCtx = null,
    allocator: Allocator,

    pub fn init(allocator: Allocator, hay: []const u8) Tokenizer {
        return .{ .allocator = allocator, .hay = hay };
    }

    pub fn next(this: *@This(), pfx: []u8) ParseErr!?Token {
        if (this.pos >= this.hay.len) {
            return null;
        }
        var c = this.hay[this.pos];
        // skip whitespace
        while (this.pos < this.hay.len and std.mem.indexOf(u8, " \t\n\r", c) > -1) {
            this.pos += 1;
            c = this.hay[this.pos];
        }
        // skip comments
        if (c == '/' and this.hay[this.pos + 1] == '*') {
            const comment_start = this.pos;
            this.pos += 2;
            c = this.hay[this.pos];
            while (!(c == '*' and this.hay[this.pos + 1] == '/')) {
                this.pos += 1;
                c = this.hay[this.pos];
                if (this.pos >= this.hay.len) {
                    // no closing tag
                    this.err = ErrCtx{
                        .code = "S0106",
                        .pos = comment_start,
                    };
                    return ParseErr.CommentDoesntEnd;
                }
            }
            this.pos += 2;
            c = this.hay[this.pos];
            return this.next(pfx); // need this to swallow any following whitespace
        }

        // test for regex
        if (pfx != true and c == '/') {
            this.err = ErrCtx{
                .code = "X0000",
                .pos = this.pos,
            };
            return ParseErr.Unimplemented;
        }

        // handle double-char operators
        if (c == '.' and this.hay[this.pos + 1] == '.') {
            this.pos += 2;
            return Token.init(this.pos, "operator", "..");
        }
        if (c == ':' and this.hay[this.pos + 1] == '=') {
            this.pos += 2;
            return Token.init(this.pos, "operator", ":=");
        }
        if (c == '!' and this.hay[this.pos + 1] == '=') {
            this.pos += 2;
            return Token.init(this.pos, "operator", "!=");
        }
        if (c == '>' and this.hay[this.pos + 1] == '=') {
            this.pos += 2;
            return Token.init(this.pos, "operator", ">=");
        }
        if (c == '<' and this.hay[this.pos + 1] == '=') {
            this.pos += 2;
            return Token.init(this.pos, "operator", "<=");
        }
        if (c == '*' and this.hay[this.pos + 1] == '*') {
            this.pos += 2;
            return Token.init(this.pos, "operator", "**");
        }
        if (c == '~' and this.hay[this.pos + 1] == '>') {
            this.pos += 2;
            return Token.init(this.pos, "operator", "~>");
        }

        // test for single char operators
        if (operators.has(&c) != null) {
            this.pos += 1;
            return Token.init(this.pos, "operator", &c);
        }

        // test for string literals
        if (c == '"' or c == '\'') {
            const qt = c; // quote type
            // double quoted string literal - find end of string
            this.pos += 1;
            var qstr = std.ArrayList(u8).init(this.arena);
            while (this.pos < this.hay.len) {
                c = this.hay[this.pos];
                if (c == '\\') {
                    this.pos += 1;
                    c = this.hay[this.pos];
                    if (escapes.has(c) != null) {
                        qstr.insert(1, escapes.has(c).?);
                    } else if (c == 'u') {
                        this.err = ErrCtx{
                            .code = "X0000",
                            .pos = this.pos,
                            .value = c,
                        };
                        // TODO
                        return ParseErr.Unimplemented; // line 219 of parser.js
                        // const b = (this.pos+1);
                        // const e = b + 4;
                        // const octets = this.hay[b..e];
                        // const OCTETS = "abcdefABCDEF0123456789";
                        // const is_octet = (
                        //   (std.mem.indexOf(u8, OCTETS, octets[0]) > -1) and
                        //   (std.mem.indexOf(u8, OCTETS, octets[1]) > -1) and
                        //   (std.mem.indexOf(u8, OCTETS, octets[2]) > -1) and
                        //   (std.mem.indexOf(u8, OCTETS, octets[3]) > -1)
                        // );
                        // if (is_octet) {
                        //   unicode.utf8Decode4(octets);
                        // }
                    } else {
                        this.err = ErrCtx{
                            .code = "S0103",
                            .pos = this.pos,
                            .token = c,
                        };
                        return ParseErr.UnsupportedEscapeSequence;
                    }
                } else if (c == qt) {
                    this.pos += 1;
                    return Token.init(this.pos, "string", qstr.items);
                }
            }
        }
        const numregex = try Regex.compile(this.arena, "^-?(0|([1-9][0-9]*))(\\.[0-9]+)?([Ee][-+]?[0-9]+)?");
        defer numregex.deinit();
        const match = try numregex.captures(this.hay[this.pos..]);
        if (match != null) {
            defer match.?.deinit();
            // this is safe to let eek out below--sliceAt() takes a slice of input to `.captures` above.
            const numraw = match.?.sliceAt(0).?;
            const num = std.fmt.parseFloat(f64, numraw) catch {
                this.err = ErrCtx{
                    .code = "S0102",
                    .pos = this.pos,
                    .token = numraw,
                };
                return ParseErr.NumOutOfRange;
            };
            if (!std.math.isNan(num) and std.math.isFinite(num)) {
                this.pos += numraw.len;
            } else {
                this.err = ErrCtx{
                    .code = "S0102",
                    .pos = this.pos,
                    .token = numraw,
                };
                return ParseErr.NumOutOfRange;
            }
        }
        // test for quoted names (backticks)
        var name: []u8 = undefined;
        if (c == '`') {
            this.pos += 1;
            const end = std.mem.indexOf(u8, this.hay[this.pos..], '`');
            if (end != -1) {
                name = this.hay[this.pos .. this.pos + end];
                this.pos += end;
                return Token.init(this.pos, "name", name);
            }
            this.err = ErrCtx{
                .code = "S0105",
                .pos = this.pos,
            };
            return ParseErr.QuotedPropertyNameUnclosed;
        }
        var i = this.pos;
        var ch: u8 = undefined;
        while (true) {
            ch = this.hay[i];
            if (i == this.hay.len or
                std.mem.indexOf(u8, " \t\n\r", c) > -1 or
                operators.has(ch))
            {
                if (this.hay[this.pos] == '$') {
                    name = this.hay[this.pos + 1 .. i];
                    this.pos = i;
                    return Token.init(this.pos, "variable", name);
                } else {
                    name = this.hay[this.pos..i];
                    this.pos = i;
                    if (case(.{ "or", "in", "and" }, name)) {
                        return Token.init(this.pos, "operator", name);
                    } else if (case(.{"true"}, name)) {
                        return Token.init(this.pos, "value", true);
                    } else if (case(.{"false"}, name)) {
                        return Token.init(this.pos, "value", false);
                    } else if (case(.{"null"}, name)) {
                        return Token.init(this.pos, "value", null);
                    } else {
                        if (this.pos == this.hay.len and name.len == 0) {
                            return null;
                        }
                        return Token.init(this.pos, "name", name);
                    }
                }
            } else {
                i += 1;
            }
        }
    }
};

fn case(comptime haystack: []const []const u8, needle: []const u8) bool {
    inline for (haystack) |wheat| {
        if (needle.len != haystack.len) {
            continue;
        }
        inline for (wheat, needle) |barley, pin| {
            if (barley != pin) {
                continue;
            }
        }
        return true;
    }

    return false;
}

test "tokenizer" {}

const Ast = struct {};

pub const Parser = struct {
    err: ?ErrCtx = null,
    arena: ArenaAllocator,
    lexer: Tokenizer,
    node: ?Token = null,
    pub fn init(allocator: Allocator, hay: []const u8) Parser {
        var arena = ArenaAllocator.init(allocator);
        return Parser{
            .arena = arena,
            .lexer = Tokenizer.init(arena.allocator(), hay),
        };
    }

    pub fn processAST(this: *@This(), token: Token) ParseErr!?Token {
        _ = this;
        _ = token;
        return null;
    }

    pub fn advance(this: *@This(), id: ?[]u8, infix: ?[]u8) ParseErr!?Token {
        _ = this;
        _ = infix;
        _ = id;

        return null;
    }

    pub fn expression(this: *@This(), rbp: u8) ParseErr!?Token {
        _ = this;
        _ = rbp;
        return null;
    }

    pub fn parse(this: *@This()) ParseErr!?Token {
        _ = try this.advance(null, null);
        var expr = (try this.expression(0)).?;
        if (!std.mem.eql(u8, this.node.?.id.?, "(end)")) {
            this.err = ErrCtx{
                .code = "S0201",
                .pos = this.node.?.pos,
                .token = this.node.?.val,
            };
            return ParseErr.SyntaxErr;
        }
        // eventually, we may split Token and ..idk, Expression?
        expr = (try this.processAST(expr)).?;
        if (!std.mem.eql(u8, expr.typ, "parent")
        //or expr.seekingParent == null
        ) {
            this.err = ErrCtx{
                .code = "S0217",
                .pos = expr.pos,
                .token = expr.typ,
            };
            return ParseErr.ParentCannotBeDerived;
        }

        return expr;
    }
};
