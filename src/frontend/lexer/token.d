module frontend.lexer.token;

import std.variant, std.stdio, std.conv;

// tipo do token
enum TokenKind
{
    // keywords (palavras chave)
    Declarar,
    Alocar,
    Const,
    Se,
    Senao,
    Retorne,
    Fim,
    Verdadeiro,
    Falso,
    Para,
    Estrutura,
    Externo,
    Ref,
    Enum,
    Parar,
    Continuar,
    Enquanto,

    // tipos
    I32,
    Int,
    Inteiro,
    I64,
    F32,
    Dec,
    Decimal,
    F64,
    F128,
    Txt,
    Vazio,
    Logico,
    Qualquer,
    Qqr,

    Identifier, // identificador
    Number, // 0-9
    Double, // 0-9.0-9
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
    Dolar, // $
    Arrow, // ->

    GreaterThan, // >
    GreaterThanEquals, // >=
    LessThan, // <
    LessThanEquals, // <=
    Or, // ||
    And, // &&
    EqualsEquals, // ==
    NotEquals, // ==

    BitAnd, // &
    BitOr, // |
    BitXor, // ^
    BitNot, // ~
    BitSHL, // <<
    BitSHR, // >>
    BitSAR, // >>>

    BitAndEquals, // &=
    BitOrEquals, // |=
    BitXorEquals, // ^=
    BitSHLEquals, // <<=
    BitSHREquals, // >>=

    PlusEquals, // +=
    MinusEquals, // -=
    StarEquals, // *=
    SlashEquals, // /=
    ModuloEquals, // %=
    TildeEquals, // ~=

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
        writeln("Loc: ", loc, "\n-----------");
    }
}

// estrutura que define dados de localização do token
struct Loc
{
    string filename; // nome do arquivo
    string dir; // diretório do arquivo
    ulong line; // linha especifica do token
    ulong start; // onde começa
    ulong end; // onde termina
}
