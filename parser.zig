const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Regex = @import("regex").Regex;
const json = std.json;
const unicode = std.unicode;

// [str] -> #
const Operators = std.ComptimeStringMap(u8, .{
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
});

// [str] -> char
const Escapes = std.ComptimeStringMap(u8, .{
    .{ "\"", '"' },
    .{ "\\", '\\' },
    .{ "/", '/' },
    .{ "b", 'b' },
    .{ "f", 'f' },
    .{ "n", 'n' },
    .{ "t", 't' },
    .{ "r", 'r' },
});

pub const ParseErr = error{
    Unimplemented, // X0000
    OOM, // X0001
    LexerRegexErr, // X0002
    NumOutOfRange, // S0102
    UnsupportedEscapeSequence, // S0103
    QuotedPropertyNameUnclosed, // S0105
    CommentDoesntEnd, // S0106
    SyntaxErr, // S0201
    UnexpectedToken, // S0202
    UnknownOperator, // S0204
    UnknownExpressionTyp, // S0205
    BadUnaryOpAttempt, // S0211
    ParentCannotBeDerived, // S0217
};

const GetTokenFn = *const fn (ctx: *Token) ParseErr!?*Token;

pub const Token = struct {
    id: []u8 = undefined,
    // ancestor: ?Token // -- this won't matter until we do processAST
    // tuple?
    // expressions?
    // steps?
    pos: usize = undefined,
    typ: []const u8 = undefined,
    val: []const u8 = undefined,
    parser: *Parser = undefined,

    nud: GetTokenFn = Token.defaultGetter,
    led: GetTokenFn = Token.defaultGetter,
    lbp: u8 = undefined,

    pub fn init(pos: usize, typ: []const u8, val: []const u8) Token {
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

pub const ErrCtx = struct {
    code: []const u8,
    pos: usize,
    value: ?[]const u8 = null,
    token: ?[]const u8 = null,
};

// TODO: after tokenization creates the Ast, how do we deinit
//       everything we created for tokenization that is now stale?

/// Tokenizer
///   takes in a raw jsonata expression string
///   yields "tokens" until the (end) token is reached.
pub const Tokenizer = struct {
    pos: usize = 0,
    hay: []const u8,
    err: ?ErrCtx = null,
    allocator: Allocator,

    pub fn init(allocator: Allocator, hay: []const u8) Tokenizer {
        return .{ .allocator = allocator, .hay = hay };
    }

    pub fn next(this: *@This(), pfx: bool) ParseErr!?Token {
        if (this.pos >= this.hay.len) return null;
        var currentChar = this.hay[this.pos..(this.pos + 1)];
        // skip whitespace
        while (this.pos < this.hay.len and std.mem.indexOf(u8, " \t\n\r", currentChar) != null) {
            this.pos += 1;
            currentChar = this.hay[this.pos..(this.pos + 1)];
        }
        // skip comments
        if (currentChar[0] == '/' and this.hay[this.pos + 1] == '*') {
            const comment_start = this.pos;
            this.pos += 2;
            currentChar = this.hay[this.pos..(this.pos + 1)];
            while (!(currentChar[0] == '*' and this.hay[this.pos + 1] == '/')) {
                this.pos += 1;
                currentChar = this.hay[this.pos..(this.pos + 1)];
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
            currentChar = this.hay[this.pos..(this.pos + 1)];
            return this.next(pfx); // need this to swallow any following whitespace
        }
        // test for regex
        if (pfx != true and currentChar[0] == '/') {
            this.err = ErrCtx{
                .code = "X0000",
                .pos = this.pos,
            };
            return ParseErr.Unimplemented;
        }
        // handle double-char operators
        if (currentChar[0] == '.' and this.hay[this.pos + 1] == '.') {
            this.pos += 2;
            return Token.init(this.pos, "operator", "..");
        }
        if (currentChar[0] == ':' and this.hay[this.pos + 1] == '=') {
            this.pos += 2;
            return Token.init(this.pos, "operator", ":=");
        }
        if (currentChar[0] == '!' and this.hay[this.pos + 1] == '=') {
            this.pos += 2;
            return Token.init(this.pos, "operator", "!=");
        }
        if (currentChar[0] == '>' and this.hay[this.pos + 1] == '=') {
            this.pos += 2;
            return Token.init(this.pos, "operator", ">=");
        }
        if (currentChar[0] == '<' and this.hay[this.pos + 1] == '=') {
            this.pos += 2;
            return Token.init(this.pos, "operator", "<=");
        }
        if (currentChar[0] == '*' and this.hay[this.pos + 1] == '*') {
            this.pos += 2;
            return Token.init(this.pos, "operator", "**");
        }
        if (currentChar[0] == '~' and this.hay[this.pos + 1] == '>') {
            this.pos += 2;
            return Token.init(this.pos, "operator", "~>");
        }
        // test for single char operators
        if (Operators.has(currentChar)) {
            this.pos += 1;
            return Token.init(this.pos, "operator", currentChar);
        }
        // test for string literals
        if (currentChar[0] == '"' or currentChar[0] == '\'') {
            const qt = currentChar; // quote type
            // double quoted string literal - find end of string
            this.pos += 1;
            var qstr = std.ArrayList(u8).init(this.allocator);
            while (this.pos < this.hay.len) {
                currentChar = this.hay[this.pos..(this.pos + 1)];
                if (currentChar[0] == '\\') {
                    this.pos += 1;
                    currentChar = this.hay[this.pos..(this.pos + 1)];
                    if (Escapes.has(currentChar)) {
                        qstr.insert(1, Escapes.get(currentChar).?) catch {
                            return ParseErr.OOM;
                        };
                    } else if (currentChar[0] == 'u') {
                        this.err = ErrCtx{
                            .code = "X0000",
                            .pos = this.pos,
                            .value = currentChar,
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
                            .token = currentChar,
                        };
                        return ParseErr.UnsupportedEscapeSequence;
                    }
                } else if (std.mem.eql(u8, currentChar, qt)) {
                    this.pos += 1;
                    return Token.init(this.pos, "string", qstr.items);
                }
            }
        }
        var numregex = Regex.compile(this.allocator, "^-?(0|([1-9][0-9]*))(\\.[0-9]+)?([Ee][-+]?[0-9]+)?") catch {
            return ParseErr.LexerRegexErr;
        };
        defer numregex.deinit();
        var match = numregex.captures(this.hay[this.pos..]) catch {
            return ParseErr.LexerRegexErr;
        };
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
                return Token.init(this.pos, "number", numraw);
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
        var name: []const u8 = undefined;
        if (currentChar[0] == '`') {
            this.pos += 1;
            const end = std.mem.indexOf(u8, this.hay[this.pos..], "`");
            if (end != null) {
                name = this.hay[this.pos .. this.pos + end.?];
                this.pos += end.?;
                return Token.init(this.pos, "name", name);
            }
            this.err = ErrCtx{
                .code = "S0105",
                .pos = this.pos,
            };
            return ParseErr.QuotedPropertyNameUnclosed;
        }
        var i = this.pos;
        var ch: []const u8 = undefined;
        while (true) {
            ch = if (i >= this.hay.len) "" else this.hay[i..(i + 1)];
            if (i == this.hay.len or
                std.mem.indexOf(u8, " \t\n\r", currentChar) != null or
                Operators.has(ch))
            {
                if (this.hay[this.pos] == '$') {
                    name = this.hay[this.pos + 1 .. i];
                    this.pos = i;
                    return Token.init(this.pos, "variable", name);
                } else {
                    name = this.hay[this.pos..i];
                    this.pos = i;
                    if (case(&[_][]const u8{ "or", "in", "and" }, name)) {
                        return Token.init(this.pos, "operator", name);
                    }
                    // TODO: true/false/null here ~> string values? I am sort of punting.
                    else if (case(&[_][]const u8{"true"}, name)) {
                        return Token.init(this.pos, "value", "true");
                    } else if (case(&[_][]const u8{"false"}, name)) {
                        return Token.init(this.pos, "value", "false");
                    } else if (case(&[_][]const u8{"null"}, name)) {
                        return Token.init(this.pos, "value", "null");
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

fn case(haystack: []const []const u8, needle: []const u8) bool {
    outer: for (haystack) |wheat| {
        if (needle.len != wheat.len) {
            continue;
        }
        for (wheat, needle) |barley, pin| {
            if (barley != pin) {
                continue :outer;
            }
        }
        return true;
    }

    return false;
}

pub const TerminalSymbol = struct {};

// unfortunately, with the way the parser was written
// with what little I know, all I can think to do is write
// a kitchen sink type that I'll probably have to clean up some day.
pub const Symbol = struct {
    id: []u8 = undefined,
    val: []u8 = undefined,
    lbp: u8 = 0,
    parser: *Parser = undefined,
    nud: *const fn (this: *@This()) Symbol,
    led: *const fn (this: *@This(), that: *Symbol) Symbol,

    const base_symbol: Symbol = .{};

    pub fn create(s: Symbol) Symbol {
        return Symbol{
            .id = s.id,
            .val = s.val,
            .lbp = s.lbp,
        };
    }
};

const SymbolTable = std.StringArrayHashMap(SymbolTable);

pub const Parser = struct {
    arena: ArenaAllocator,
    lexer: Tokenizer,
    node: *anyopaque = undefined,
    symbol_table: SymbolTable,
    err: ?ErrCtx = null,
    errors: std.ArrayList(ErrCtx),

    pub fn symbol(this: *@This(), id: []u8, bp: u8) Symbol {
        var s: ?Token = this.symbol_table.get(id);
        if (s != null) {
            if (bp >= s.?.lbp) {
                s.?.lbp = bp;
            }
        } else {
            s = Symbol.create(Symbol.base_symbol);
            s.id = id;
            s.val = id;
            s.lbp = bp;
            this.symbol_table.put(id, s);
        }

        return s;
    }

    pub fn init(allocator: Allocator, hay: []const u8) Parser {
        var arena = ArenaAllocator.init(allocator);
        return Parser{
            .arena = arena,
            .lexer = Tokenizer.init(arena.allocator(), hay),
            .symbol_table = SymbolTable.init(allocator),
            .errors = std.ArrayList(ErrCtx).init(arena.allocator()),
        };
    }
    pub fn processAST(this: *@This(), token: Token) ParseErr!?Token {
        _ = this;
        _ = token;
        return null;
    }

    pub fn advance(this: *@This(), id: ?[]const u8, infix: bool) ParseErr!?Token {
        if (id != null and std.mem.eql(u8, this.node.?.id.?, id.?)) {
            this.setErr(ErrCtx{
                .code = "S0202",
                .pos = this.node.?.pos,
                .token = this.node.?.val,
                .value = id.?,
            });
            return ParseErr.UnexpectedToken;
        }
        var next_token = try this.lexer.next(infix);
        if (next_token == null) {
            this.node = this.symbol_table.get("(end)");
            this.node.?.pos = this.lexer.hay.len;
            return this.node.?;
        }
        var val = next_token.?.val;
        const typ: []const u8 = next_token.?.typ;
        var symb: Token = undefined;
        switch (Parser.caseAdvance(typ)) {
            .NameVariable => {
                symb = this.symbol_table.get("(name)");
            },
            .Operator => {
                symb = this.symbol_table.get(val);
                if (!symb) {
                    this.err = ErrCtx{
                        .code = "S0204",
                        .pos = next_token.?.pos,
                        .token = val,
                    };
                    return ParseErr.UnknownOperator;
                }
            },
            .StringNumberValue => {
                symb = this.symbol_table.get("(literal)");
            },
            .Regex => {
                typ = "";
                symb = this.symbol_table.get("(regex)");
            },
            else => {
                this.err = ErrCtx{
                    .code = "S0205",
                    .pos = next_token.?.pos,
                    .token = val,
                };
                return ParseErr.UnknownExpressionTyp;
            },
        }

        this.node = Token.init(symb.pos, symb.typ, symb.val);
        this.node.?.val = val;
        this.node.?.pos = next_token.?.pos;
        return this.node;
    }

    const AdvanceSwitch1 = enum { NameVariable, Operator, StringNumberValue, Regex, Other };
    pub fn caseAdvance(typ: []const u8) AdvanceSwitch1 {
        return switch (typ[0]) {
            'o' => if (std.mem.eql(u8, "perator", typ[1..])) AdvanceSwitch1.Operator else AdvanceSwitch1.Other,
            'n' => switch (typ[1]) {
                'u' => if (std.mem.eql(u8, "mber", typ[2..])) AdvanceSwitch1.StringNumberValue else AdvanceSwitch1.Other,
                'a' => if (std.mem.eql(u8, "me", typ[2..])) AdvanceSwitch1.NameVariable else AdvanceSwitch1.Other,
                else => AdvanceSwitch1.Other,
            },
            's' => switch (typ[1]) {
                't' => if (std.mem.eql(u8, "ring", typ[2..])) AdvanceSwitch1.StringNumberValue else AdvanceSwitch1.Other,
                else => AdvanceSwitch1.Other,
            },
            'v' => switch (typ[1]) {
                'a' => if (std.mem.eql(u8, "lue", typ[2..])) AdvanceSwitch1.StringNumberValue else AdvanceSwitch1.Other,
                else => AdvanceSwitch1.Other,
            },
            else => AdvanceSwitch1.Other,
        };
    }

    pub fn expression(this: *@This(), rbp: u8) ParseErr!?Token {
        var left: Token = undefined;
        var t: Token = this.node;
        _ = try this.advance(null, true);
        left = t.nud();
        while (rbp < this.node.?.lbp) {
            t = this.node.?;
            this.advance(null, false);
            left = t.led();
        }
        return null;
    }

    pub fn parse(this: *@This()) ParseErr!?Token {
        _ = try this.advance(null, false);
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
        // or expr.seekingParent == null
        ) {
            this.setErr(ErrCtx{
                .code = "S0217",
                .pos = expr.pos,
                .token = expr.typ,
            });
            return ParseErr.ParentCannotBeDerived;
        }

        return expr;
    }
};
