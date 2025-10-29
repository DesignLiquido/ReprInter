module frontend.lexer.token;

import std.variant, std.stdio, std.conv;

// tipo do token
enum TokenKind
{
    // keywords (palavras chave)
    // nenhuma ainda

    // tipos
    I32,
    I64,
    F32,
    F64,
    F128,

    Identifier, // identificador
    Number, // 0-9
    String, // "FernandoDev"

    // simbolos
    LParen, // (
    RParen, // )
    LBrace, // {
    RBrace, // }
    LBracket, // [
    RBracket, // ]
    Plus, // +
    PlusPlus, // ++
    Minus, // -
    MinusMinus, // --
    Star, // *
    Ampersand, // &
    Slash, // /
    Comma, // ,
    Colon, // :
    SemiColon, // ;
    Equals, // =
    Dot, // .
    Range, // ..
    Variadic, // ...
    RangeEquals, // ..=
    Bang, // !
    Modulo, // %

    GreaterThan, // >
    GreaterThanEquals, // >=
    LessThan, // <
    LessThanEquals, // <=
    Or, // ||
    And, // &&
    PlusEquals, // +=
    Arrow, // ->

    EqualsEquals, // ==

    Eof // EndOfFile (FimDoArquivo)
}

// estrutura do Token
struct Token
{
    TokenKind kind; // tipo do token
    Variant value; // valor bruto
    Loc loc; // dados de localização do token

    void print()
    {
        writeln("TokenKind: ", to!string(kind));
        writeln("TokenValue: ", to!string(value));
        writeln("Loc: ", loc);
    }
}

struct Loc
{
    string filename; // nome do arquivo
    string dir; // diretório do arquivo
    ulong line; // linha especifica do token
    ulong start; // onde começa
    ulong end; // onde termina
}
