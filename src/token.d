module token;

import std.format;

enum TokenKind : ubyte
{
    // keywords
    Imediato,
    Aloca,
    Soma,
    Retorne,
    Funcao,
    Estrutura,
    Chamada,
    Converter,

    // literals
    Id, // $x
    Identifier, // x
    Int, // 0..9
    Double, // 0.0
    String, // "dev"

    // symbols
    LBrace,
    RBrace,
    LParen,
    RParen,
    Comma,
    Dot,
    Variadic, // ...
    Colon,
    SemiColon,

    // eof
    Eof,
}

union TokenRaw
{
    long i;
    double d;
    dstring s;

    pragma(inline, true)
    static TokenRaw _i(long n)
    {
        TokenRaw _;
        _.i = n;
        return _;
    }

    pragma(inline, true)
    static TokenRaw _d(double n)
    {
        TokenRaw _;
        _.d = n;
        return _;
    }

    pragma(inline, true)
    static TokenRaw _s(dstring n)
    {
        TokenRaw _;
        _.s = n;
        return _;
    }
}

class PosLine
{
    uint offset;
    uint line;

    this(uint o, uint l)
    {
        offset = o;
        line = l;
    }
}

class Position
{
    string filename;
    PosLine start, end;

    this(string f, PosLine s, PosLine e)
    {
        filename = f;
        start = s;
        end = e;
    }

    string toStr()
    {
        return format("{ %s:%d:%d }", filename, start.line, start.offset);
    }
}

class Token
{
    TokenKind kind;
    TokenRaw value;
    Position pos;

    this(TokenKind k, TokenRaw r, Position p)
    {
        kind = k;
        value = r;
        pos = p;
    }

    pragma(inline, true)
    void print()
    {
        import std.stdio : writeln;

        writeln("[TOKEN]\n    kind = ", kind, "\n    value = ", value, "\n    pos = ", pos.toStr());
    }
}
