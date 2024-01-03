const std = @import("std");
const json = std.json;

// [str] -> #
const operators = std.StringHashMap(u8){};
comptime {
  operators.put(".", 75);
  operators.put("[", 80);
  operators.put("]", 0);
  operators.put("{", 70);
  operators.put("}", 0);
  operators.put("(", 80);
  operators.put(")", 0);
  operators.put(",", 0);
  operators.put("@", 80);
  operators.put("#", 80);
  operators.put(";", 80);
  operators.put(":", 80);
  operators.put("?", 20);
  operators.put("+", 50);
  operators.put("-", 50);
  operators.put("*", 60);
  operators.put("/", 60);
  operators.put("%", 60);
  operators.put("|", 20);
  operators.put("=", 40);
  operators.put("<", 40);
  operators.put(">", 40);
  operators.put("^", 40);
  operators.put("**", 60);
  operators.put("..", 20);
  operators.put(":=", 10);
  operators.put("!=", 40);
  operators.put("<=", 40);
  operators.put(">=", 40);
  operators.put("~>", 40);
  operators.put("and", 30);
  operators.put("or", 25);
  operators.put("in", 40);
  operators.put("&", 50);
  operators.put("!", 0);   // not an operator, but needed as a stop character for name token
  operators.put("~", 0);   // not an operator, but needed as a stop character for name token
}

// [str] -> char
const escapes = std.StringHashMap(u8){};
comptime {
  escapes.put("\"", '"');
  escapes.put("\\", '\\');
  escapes.put("/", '/');
  escapes.put("b", 'b');
  escapes.put("f", 'f');
  escapes.put("n", 'n');
  escapes.put("t", 't');
  escapes.put("r", 'r');
}

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
  hay: []u8,
  err: ?ErrCtx = null,
  arena: std.heap.ArenaAllocator,

  pub fn create(arena: std.heap.ArenaAllocator, hay: []u8) Tokenizer {
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
    if (operators.get(&c)) {
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
    }
  }
};

test "tokenizer" {

}

const Ast = struct {};

const Parser = struct {
  arena: std.heap.ArenaAllocator,
  lexer: Tokenizer,
  pub fn create(allocator: std.mem.Allocator, hay: []u8) Parser {
    return .{
      .arena = std.heap.ArenaAllocator.init(allocator),
      .lexer = Tokenizer.create(hay),
    };
  }

  pub fn parse(this: *@This()) !?Ast {
    _ = this;
    return null;
  }
};