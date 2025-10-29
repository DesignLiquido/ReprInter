module frontend.lexer.lexer;

import std.stdio, std.conv, std.variant, std.ascii, std.format, std.exception;
import frontend.lexer.token, erro;

class Lexer
{
private:
    string source = ""; // todo o conteudo bruto
    string filename = ""; // nome do arquivo que o Lexer está tratando
    string dir = "."; // diretório padrão
    long offset = 0; // offset relativo ao arquivo
    long line = 1; // numero da linha
    long lineOffset = 0; // offset relativo a linha
    Token[] tokens = []; // onde os tokens ficarão armazenados
    TokenKind[string] keywords; // tabela de palavras chave
    TokenKind[string] symbols; // tabela de simbolos
    DiagnosticError error; // classe de erro (instancia global)

    void setKeywords()
    {
        // palavras chave

        // tipos
        keywords["i32"] = TokenKind.I32;
        keywords["i64"] = TokenKind.I64;
        keywords["f32"] = TokenKind.F32;
        keywords["f64"] = TokenKind.F64;
        keywords["f128"] = TokenKind.F128;
    }

    // define todos os simbolos da representação intermediaria em uma tabela
    void setSymbols()
    {
        symbols["("] = TokenKind.LParen;
        symbols[")"] = TokenKind.RParen;
        symbols["{"] = TokenKind.LBrace;
        symbols["}"] = TokenKind.RBrace;
        symbols["["] = TokenKind.LBracket;
        symbols["]"] = TokenKind.RBracket;
        symbols["+"] = TokenKind.Plus;
        symbols["-"] = TokenKind.Minus;
        symbols["*"] = TokenKind.Star;
        symbols["/"] = TokenKind.Slash;
        symbols[":"] = TokenKind.Colon;
        symbols[","] = TokenKind.Comma;
        symbols[";"] = TokenKind.SemiColon;
        symbols["="] = TokenKind.Equals;
        symbols[">"] = TokenKind.GreaterThan;
        symbols[">="] = TokenKind.GreaterThanEquals;
        symbols["<"] = TokenKind.LessThan;
        symbols["<="] = TokenKind.LessThanEquals;
        symbols["=="] = TokenKind.EqualsEquals;
        symbols["."] = TokenKind.Dot;
        symbols["!"] = TokenKind.Bang;
        symbols["%"] = TokenKind.Modulo;
        symbols["&"] = TokenKind.Ampersand;

        // 2
        symbols["||"] = TokenKind.Or;
        symbols["&&"] = TokenKind.And;
        symbols[".."] = TokenKind.Range;
        symbols["++"] = TokenKind.PlusPlus;
        symbols["--"] = TokenKind.MinusMinus;
        symbols["+="] = TokenKind.PlusEquals;
        symbols["->"] = TokenKind.Arrow;

        // 3
        symbols["..."] = TokenKind.Variadic;
        symbols["..="] = TokenKind.RangeEquals;
    }

    bool lexChar(char c)
    {
        string ch = to!string(c);

        if (offset + 2 < source.length)
        {
            string three = ch ~ source[offset + 1] ~ source[offset + 2];
            if (three in symbols)
            {
                createToken(symbols[three], Variant(three), three.length);
                return true;
            }
        }

        if (offset + 1 < source.length)
        {
            string two = ch ~ source[offset + 1];
            if (two in symbols)
            {
                createToken(symbols[two], Variant(two), two.length);
                return true;
            }
        }

        if (ch in symbols)
        {
            createToken(symbols[ch], Variant(ch), 1);
            return true;
        }

        return false;
    }

    Loc createLoc(ulong len, long line_ = -1)
    {
        return Loc(filename, dir, line_ == -1 ? line : line_, lineOffset - len + 1, lineOffset);
    }

    void createToken(TokenKind kind, Variant value, ulong len)
    {
        tokens ~= Token(kind, value, createLoc(len));
    }

    void advance(int count = 1)
    {
        for (int i; i < count; i++)
        {
            if (offset < source.length)
            {
                if (source[offset] == '\n')
                {
                    line++;
                    lineOffset = 0;
                }
                else
                    lineOffset++;
                offset++;
            }
        }
    }

    char peek(int lookahead = 0)
    {
        long pos = offset + lookahead;
        return (pos < source.length) ? source[pos] : '\0';
    }

public:
    this(string filename = "", string source = "", string dir = ".", DiagnosticError error)
    {
        this.filename = filename;
        this.source = source;
        this.dir = dir;
        this.error = error;
        setKeywords(); // faz o startup das palavras chave
        setSymbols(); // faz o startup dos simbolos
    }

    Token[] tokenize()
    {
        while (offset < source.length)
        {
            char ch = source[offset];

            if (ch == '\n')
            {
                advance();
                continue;
            }

            if (isWhite(ch))
            {
                advance();
                continue;
            }

            if (isAlpha(ch) || ch == '_')
            {
                // long startOffset = lineOffset;
                string id;

                while (offset < source.length && (isAlpha(peek()) || peek() == '_' || isDigit(
                        peek())))
                {
                    id ~= to!string(peek());
                    advance();
                }

                if (id in keywords)
                    createToken(keywords[id], Variant(id), id.length + 1);
                else
                    createToken(TokenKind.Identifier, Variant(id), id.length + 1);
                continue;
            }

            if (isDigit(ch))
            {
                // long startOffset = lineOffset;
                string n;
                bool isDouble = false;

                while (offset < source.length && (isDigit(peek()) || peek() == '_'))
                {
                    if (peek() != '_')
                        n ~= to!string(peek());
                    advance();
                }

                if (offset < source.length && peek() == '.' && source[offset + 1] != '.')
                {
                    n ~= ".";
                    advance();
                    isDouble = true;

                    while (offset < source.length && isDigit(peek()))
                    {
                        n ~= to!string(peek());
                        advance();
                    }
                }

                if (offset < source.length)
                {
                    char suffix = peek();
                    if (suffix == 'F' || suffix == 'f')
                    {
                        advance();
                        createToken(TokenKind.F32, Variant(n), n.length + 1);
                    }
                    else if (suffix == 'D' || suffix == 'd')
                    {
                        advance();
                        createToken(TokenKind.F64, Variant(n), n.length + 1);
                    }
                    else if (suffix == 'L')
                    {
                        advance();
                        createToken(TokenKind.F128, Variant(n), n.length + 1);
                    }
                    else if (isDouble)
                        createToken(TokenKind.F64, Variant(n), n.length + 1);
                    else
                        createToken(TokenKind.I64, Variant(n), n.length + 1);
                }
                else
                {
                    if (isDouble)
                        createToken(TokenKind.F64, Variant(n), n.length + 1);
                    else
                        createToken(TokenKind.I64, Variant(n), n.length + 1);
                }
                continue;
            }

            if (ch == '/' && offset + 1 < source.length && source[offset + 1] == '/')
            {
                while (offset < source.length && peek() != '\n')
                    advance();
                continue;
            }

            if (lexChar(ch))
            {
                if (offset + 2 < source.length)
                {
                    string three = to!string(ch) ~ source[offset + 1] ~ source[offset + 2];
                    if (three in symbols)
                    {
                        advance(3);
                        continue;
                    }
                }

                if (offset + 1 < source.length)
                {
                    string two = to!string(ch) ~ source[offset + 1];
                    if (two in symbols)
                    {
                        advance(2);
                        continue;
                    }
                }
                advance();
                continue;
            }

            // Strings
            if (ch == '"')
            {
                long line_ = line;
                advance();
                string buff;

                while (offset < source.length && peek() != '"')
                {
                    char pk = peek();

                    // Trata escapes
                    if (pk == '\\')
                    {
                        advance(); // consome o '\'

                        if (offset >= source.length)
                        {
                            error.addError(Diagnostic("Sequência de escape incompleta no final do arquivo",
                                    createLoc(1, line_)));
                            break;
                        }

                        char escaped = peek();

                        switch (escaped)
                        {
                        case 'n':
                            buff ~= '\n';
                            break;
                        case 't':
                            buff ~= '\t';
                            break;
                        case 'r':
                            buff ~= '\r';
                            break;
                        case '\\':
                            buff ~= '\\';
                            break;
                        case '"':
                            buff ~= '"';
                            break;
                        case '0':
                            buff ~= '\0';
                            break;
                        case 'b':
                            buff ~= '\b';
                            break;
                        case 'f':
                            buff ~= '\f';
                            break;
                        case 'v':
                            buff ~= '\v';
                            break;
                        case '\'':
                            buff ~= '\'';
                            break;
                        case 'x':
                            // Escape hexadecimal: \xHH
                            advance(); // consome 'x'
                            if (offset + 1 < source.length)
                            {
                                string hexStr = source[offset .. offset + 2];
                                try
                                {
                                    int hexValue = parse!int(hexStr, 16);
                                    buff ~= cast(char) hexValue;
                                    advance(); // consome primeiro dígito
                                }
                                catch (Exception e)
                                {
                                    error.addError(Diagnostic(
                                            format("Sequencia hexadecimal invalida \\x%s", hexStr),
                                            createLoc(1, line_)
                                    ));
                                    buff ~= 'x'; // fallback
                                }
                            }
                            else
                            {
                                error.addError(Diagnostic(
                                        "Sequencia hexadecimal incompleta",
                                        createLoc(1, line_)
                                ));
                                buff ~= 'x';
                            }
                            break;
                        case 'u':
                            // Escape Unicode: \uHHHH
                            advance(); // consome 'u'
                            if (offset + 3 < source.length)
                            {
                                string hexStr = source[offset .. offset + 4];
                                try
                                {
                                    int unicodeValue = parse!int(hexStr, 16);
                                    import std.utf : encode;

                                    char[4] utf8Buf;
                                    size_t len = encode(utf8Buf, cast(dchar) unicodeValue);
                                    buff ~= utf8Buf[0 .. len];
                                    advance();
                                    advance();
                                    advance(); // consome 3 dígitos (o 4º é consumido no final)
                                }
                                catch (Exception e)
                                {
                                    error.addError(Diagnostic(
                                            format("Sequencia de escape unicode inválida \\u%s", hexStr),
                                            createLoc(1, line_)
                                    ));
                                    buff ~= 'u';
                                }
                            }
                            else
                            {
                                error.addError(Diagnostic(
                                        "Escape unicode incompleto",
                                        createLoc(1, line_)
                                ));
                                buff ~= 'u';
                            }
                            break;
                        default:
                            // Escape inválido - mantém o caractere literal
                            error.addError(Diagnostic(
                                    format("Sequencia de escape desconhecida \\%s", escaped),
                                    createLoc(1, line_)
                            ));
                            buff ~= escaped;
                            break;
                        }
                        advance(); // consome o caractere escapado
                    }
                    else if (pk == '\n')
                    {
                        // String multilinha literal (sem escape)
                        buff ~= '\n';
                        line++;
                        advance();
                    }
                    else
                    {
                        buff ~= pk;
                        advance();
                    }
                }

                if (offset < source.length && peek() == '"')
                {
                    advance();
                    createToken(TokenKind.String, Variant(buff), buff.length + 3);
                }
                else
                {
                    error.addError(Diagnostic("String não terminada", createLoc(1, line_)));
                    createToken(TokenKind.String, Variant(buff), buff.length + 1);
                }
                continue;
            }
            error.addError(Diagnostic(format("Caractere inválido '%c'", ch), createLoc(1)));
            advance();
        }

        tokens ~= Token(TokenKind.Eof, Variant(null));
        return tokens;
    }
}
