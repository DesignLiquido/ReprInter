module lexer;

import std.utf : decodeFront, decode;
import std.exception : enforce;
import std.format;
import std.stdio;
import std.array;
import std.conv;

import token;
import errors;

alias String = Appender!dstring;
alias Tokens = Appender!(Token[]);

class Lexer
{
private:
    Diagnostics err;
    Tokens tokens;
    
    string source, filename;
    uint offset, l_offset;
    uint line = 1;
    
    immutable TokenKind[dstring] keywords = [
        "alocar": TokenKind.Aloca,
        "alocarn": TokenKind.Alocan,

        "estrutura": TokenKind.Estrutura,
        "chamada": TokenKind.Chamada,
        
        "soma": TokenKind.Soma,
        "sub": TokenKind.Sub,
        "subtracao": TokenKind.Sub,
        "subtração": TokenKind.Sub,
        "mul": TokenKind.Mul,
        "multiplicacao": TokenKind.Mul,
        "multiplicação": TokenKind.Mul,
        "div": TokenKind.Div,
        "divisão": TokenKind.Div,
        "mod": TokenKind.Mod,
        "modulo": TokenKind.Mod,

        "ref": TokenKind.Ref,
        "referencia": TokenKind.Ref,

        "deref": TokenKind.Deref,
        "dereferencia": TokenKind.Deref,
        
        "escreva": TokenKind.Escreva,
        
        "conv": TokenKind.Converter,
        "converter": TokenKind.Converter,
        "setar": TokenKind.Setar,
        "obter": TokenKind.Obter,
        "salte": TokenKind.Salte,
        "saltez": TokenKind.Saltez,
        "saltenz": TokenKind.Saltenz,
        "compare": TokenKind.Compare,
        "fn": TokenKind.Funcao,
        "funcao": TokenKind.Funcao,
        "função": TokenKind.Funcao,
        "ime": TokenKind.Imediato,
        "imediato": TokenKind.Imediato,
        "ret": TokenKind.Retorne,
        "retorne": TokenKind.Retorne,
    ];

public:
    this(string source, string filename, Diagnostics err)
    {
        this.source = source;
        this.filename = filename;
        this.err = err;
    }

    bool isAlpha(dchar c)
    {
        return (c >= 'a' && c <= 'z')
            || (c >= 'A' && c <= 'Z')
            || c == '_' // validação para caracteres especiais
            || (c >= 192 && c <= 214)
            || (c >= 216 && c <= 246)
            || (c >= 248 && c <= 255);
    }

    bool isNumeric(dchar c)
    {
        return c >= '0' && c <= '9';
    }

    bool isAlphaNumeric(dchar c)
    {
        return isNumeric(c) || isAlpha(c);
    }

    bool isAtEnd(uint n = 0)
    {
        return (offset + n) >= source.length;
    }

    void checkIsAtEnd(uint n = 0)
    {
        enforce(!isAtEnd(n), "Source out of bounds in lexer.");
    }

    dchar future(uint n)
    {
        checkIsAtEnd(n);
        return source[offset + n];
    }

    dchar advance()
    {
        checkIsAtEnd();
        l_offset++;
        return decodeFront(source);
    }

    dchar peek()
    {
        checkIsAtEnd();
        size_t i;
        return decode(source, i);
    }

    bool match(dchar ch)
    {
        checkIsAtEnd();
        if (peek() == ch)
        {
            advance();
            return true;
        }
        return false;
    }

    dstring lexNumer(dchar ch, uint start, out bool isDouble, out bool dotInvalid, bool d = true)
    {
        String buffer = String();
        buffer.reserve(20); // se precisar de mais ele irá realocar automaticamente
        buffer.put([ch]);
        while (!isAtEnd() && (isNumeric(peek()) || peek() == '.'))
        {
            if (!d && peek() == '.')
            {
                err.error(getPosition(start, line), "Sem permissão para numeros flutuantes.");
                continue;
            }
            if (peek() == '.' && isDouble)
            {
                dotInvalid = true;
                advance();
                continue;
            }
            if (peek() == '.' && !isDouble)
                isDouble = true;
            buffer.put([advance()]);
        }
        return buffer.data;
    }

    Position getPosition(uint s, uint l)
    {
        return new Position(filename, new PosLine(s, l), new PosLine(l_offset, line));
    }

    Token[] tokenizer()
    {
        while (!isAtEnd())
        {
            bool did;
            dchar ch = advance();

            if (ch == '\r' || ch == ' ' || ch == '\t')
                continue;

            if (ch == '\n')
            {
                line++;
                l_offset = 0;
                continue;
            }

            if (isNumeric(ch))
            {
                uint start = l_offset;
                bool isDouble;
                bool dotInvalid;
                dstring buffer = lexNumer(ch, start, isDouble, dotInvalid);

                if (dotInvalid)
                {
                    err.error(getPosition(start, line), "Uso de '.' inválido.");
                    continue;
                }

                TokenKind kind = TokenKind.Int;
                TokenRaw raw;

                if (isDouble)
                {
                    kind = TokenKind.Double;
                    raw.d = to!double(buffer);
                }
                else
                    raw.i = to!long(buffer);

                tokens.put(new Token(kind, raw, getPosition(start, line)));
                continue;
            }

            if (ch == '$')
            {
                did = true;
                ch = advance();
            }

            if (isAlpha(ch))
            {
                uint start = did ? l_offset - 1 : l_offset;
                String buffer = String();
                buffer.reserve(64);
                buffer.put([ch]);

                while (!isAtEnd() && isAlphaNumeric(peek()))
                    buffer.put([advance()]);

                TokenKind kind = did ? TokenKind.Id : TokenKind.Identifier;
                if (!did)
                    if (immutable TokenKind* k = buffer.data in keywords)
                        kind = *k;

                tokens.put(new Token(kind, TokenRaw._s(buffer.data), getPosition(start, line)));
                continue;
            }

            if (ch == '"')
            {
                uint start = l_offset;
                uint l = line;
                String buffer = String();
                buffer.reserve(64);

                while (!isAtEnd() && peek() != '"')
                {
                    if (peek() == '\\')
                    {
                        advance(); // consume '\'
                        if (isAtEnd())
                            break;
                        switch (peek())
                        {
                        case 'n':
                            buffer.put('\n');
                            advance();
                            break;
                        case 'r':
                            buffer.put('\r');
                            advance();
                            break;
                        case 't':
                            buffer.put('\t');
                            advance();
                            break;
                        case '"':
                            buffer.put('"');
                            advance();
                            break;
                        case '\\':
                            buffer.put('\\');
                            advance();
                            break;
                        default:
                            err.error(getPosition(l_offset, line),
                                format("Escape inválido: '\\%c'", peek()));
                            advance();
                            break;
                        }
                        continue;
                    }

                    if (peek() == '\n')
                    {
                        line++;
                        l_offset = 0;
                    }
                    buffer.put([advance()]);
                }

                if (isAtEnd() || !match('"'))
                {
                    err.error(getPosition(start, l), "String não foi fechada.");
                    return tokens.data;
                }

                tokens.put(new Token(TokenKind.String, TokenRaw._s(buffer.data), getPosition(start, l)));
                continue;
            }

            TokenKind k = TokenKind.Eof;
            uint start = l_offset;

            switch (ch)
            {
            case '/':
                if (match('/'))
                {
                    while (!isAtEnd())
                        if (peek() != '\n')
                            advance();
                        else
                            break;
                    continue;
                }
                break;
            case '<':
                k = TokenKind.LThan;
                if (peek() == '=')
                {
                    k = TokenKind.LEquals;
                    advance();
                }
                break;
            case '>':
                k = TokenKind.GThan;
                if (peek() == '=')
                {
                    k = TokenKind.GEquals;
                    advance();
                }
                break;
            case '=':
                k = TokenKind.EEquals;
                if (peek() != '=')
                    err.error(getPosition(start, line), "Simbolo inválido, '=' não é permitido.");
                advance();
                break;
            case '!':
                k = TokenKind.NEquals;
                if (peek() != '=')
                    err.error(getPosition(start, line), "Simbolo inválido, '!' não é permitido.");
                advance();
                break;
            case '(':
                k = TokenKind.LParen;
                break;
            case ')':
                k = TokenKind.RParen;
                break;
            case '{':
                k = TokenKind.LBrace;
                break;
            case '}':
                k = TokenKind.RBrace;
                break;
            case ',':
                k = TokenKind.Comma;
                break;
            case ':':
                k = TokenKind.Colon;
                break;
            case ';':
                k = TokenKind.SemiColon;
                break;
            case '.':
                k = TokenKind.Dot;
                if (peek() == '.' && future(1) == '.')
                {
                    k = TokenKind.Variadic;
                    advance();
                    advance();
                }
                break;
            default:
                break;
            }

            if (k == TokenKind.Eof)
            {
                err.error(getPosition(start, line), format("Char desconhecido: '%c'", ch));
                continue;
            }

            tokens.put(new Token(k, TokenRaw.init, getPosition(start, line)));
        }
        return tokens.data;
    }
}
