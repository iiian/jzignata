const std = @import("std");
const json = std.json;

// [str] -> #
const operators = std.ComptimeStringMap(u8, .{
  .{".", 75},
  .{"[", 80},
  .{"]", 0},
  .{"{", 70},
  .{"}", 0},
  .{"(", 80},
  .{")", 0},
  .{",", 0},
  .{"@", 80},
  .{"#", 80},
  .{";", 80},
  .{":", 80},
  .{"?", 20},
  .{"+", 50},
  .{"-", 50},
  .{"*", 60},
  .{"/", 60},
  .{"%", 60},
  .{"|", 20},
  .{"=", 40},
  .{"<", 40},
  .{">", 40},
  .{"^", 40},
  .{"**", 60},
  .{"..", 20},
  .{":=", 10},
  .{"!=", 40},
  .{"<=", 40},
  .{">=", 40},
  .{"~>", 40},
  .{"and", 30},
  .{"or", 25},
  .{"in", 40},
  .{"&", 50},
  .{"!", 0},   // not an operator, but needed as a stop character for name token
  .{"~", 0},   // not an operator, but needed as a stop character for name token
}){};

// [str] -> char
const escapes = std.ComptimeStringMap(u8, .{
  .{"\"", '"'},
  .{"\\", '\\'},
  .{"/", '/'},
  .{"b", 'b'},
  .{"f", 'f'},
  .{"n", 'n'},
  .{"t", 't'},
  .{"r", 'r'},
}){};

const ParseErr = error {
  Unimplemented, // X0000
  CommentDoesntEnd, // S0106
};

const Token = struct {
  pos: u32,
  typ: []u8,
  val: []u8,

  pub fn create(pos: u32, typ: []u8, val: []u8) Token {
    return Token {
      .pos = pos,
      .typ = typ,
      .val = val,
    };
  }
};

const ErrCtx = struct {
  code: []u8,
  pos: usize,
  value: ?[]u8 = null,
};

/// Tokenizer
///   takes in a raw jsonata expression string
///   yields "tokens" until the (end) token is reached.
const Tokenizer = struct {
  pos: usize = 0,
  hay: []const u8,
  err: ?ErrCtx = null,
  arena: std.heap.ArenaAllocator,

  pub fn create(arena: std.heap.ArenaAllocator, hay: []const u8) Tokenizer {
    return .{
      .arena = arena,
      .hay = hay
    };
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
      while (!(c == '*' and this.hay[this.pos+1] == '/')) {
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
      return Token.create(this.pos, "operator", "..");
    }
    if (c == ':' and this.hay[this.pos + 1] == '=') {
      this.pos += 2;
      return Token.create(this.pos, "operator", ":=");
    }
    if (c == '!' and this.hay[this.pos + 1] == '=') {
      this.pos += 2;
      return Token.create(this.pos, "operator", "!=");
    }
    if (c == '>' and this.hay[this.pos + 1] == '=') {
      this.pos += 2;
      return Token.create(this.pos, "operator", ">=");
    }
    if (c == '<' and this.hay[this.pos + 1] == '=') {
      this.pos += 2;
      return Token.create(this.pos, "operator", "<=");
    }
    if (c == '*' and this.hay[this.pos + 1] == '*') {
      this.pos += 2;
      return Token.create(this.pos, "operator", "**");
    }
    if (c == '~' and this.hay[this.pos + 1] == '>') {
      this.pos += 2;
      return Token.create(this.pos, "operator", "~>");
    }

    // test for single char operators
    if (operators.get(&c) != null) {
      this.pos += 1;
      return Token.create(this.pos, "operator", &c);
    }

    // test for string literals
    if (c == '"' or c == '\'') {
      const qt = c;
      _ = qt; // quote type
      // double quoted string literal - find end of string
      this.pos += 1;
      var qstr = std.ArrayList(u8).init(this.arena);
      defer qstr.deinit();
      while (this.pos < this.hay.len) {
        c = this.hay[this.pos];
        if (c == '\\') {
          this.pos += 1;
          c = this.hay[this.pos];
          if (escapes.get(c) != null) {

          }
        }
      }
    }
  }
};

test "tokenizer" {

}

const Ast = struct {};

pub const Parser = struct {
  arena: std.heap.ArenaAllocator,
  lexer: Tokenizer,
  pub fn create(allocator: std.mem.Allocator, hay: []const u8) Parser {
    const arena = std.heap.ArenaAllocator.init(allocator);
    return .{
      .arena = arena,
      .lexer = Tokenizer.create(arena, hay),
    };
  }

  pub fn parse(this: *@This()) !?Ast {
    _ = this;
    return null;
  }
};