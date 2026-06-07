module parser;

import std.conv : to;
import std.format;
import std.stdio;

import type_registry;
import context;
import errors;
import htype;
import token;
import utils;
import ast;

class Parser
{
private:
    Diagnostics err;
    TypeRegistry registry;
    Token[] tokens;
    uint offset;
    Context context;

    void h_validar(bool cond, string message, Position pos)
    {
        if (cond)
            return;
        err.error(pos, message);
    }

    void checkType(HType exp, HType rec, Position pos)
    {
        string s1 = exp.toStr();
        string s2 = rec.toStr();
        if (s1 == s2)
            return;
        err.error(pos, format("Tipos incompativeis, era esperado '%s' e foi recebido '%s'.", s1, s2));
    }

    bool isAtEnd()
    {
        return offset >= tokens.length || tokens[offset].kind == TokenKind.Eof;
    }

    Token peek()
    {
        return tokens[offset];
    }

    Token previous()
    {
        return tokens[offset - 1];
    }

    Token advance()
    {
        if (!isAtEnd())
            offset++;
        return previous();
    }

    bool check(TokenKind k)
    {
        return !isAtEnd() && peek().kind == k;
    }

    bool match(TokenKind k)
    {
        if (check(k))
        {
            advance();
            return true;
        }
        return false;
    }

    void expectComma()
    {
        expect(TokenKind.Comma, "Esperado ','");
    }

    Token expectId()
    {
        return expect(TokenKind.Id, "Esperado um identificador com prefixo '$'.");
    }

    Token expect(TokenKind k, string msg)
    {
        if (check(k))
            return advance();
        err.error(peek().pos, format("%s (encontrado: %s)", msg, peek().kind));
        return advance();
    }

    Node parseExpr()
    {
        Token tk = advance();
        switch (tk.kind)
        {
        case TokenKind.Int:
            return new IntLit(tk.value.i, tk.pos);

        case TokenKind.Double:
            return new DoubleLit(tk.value.d, tk.pos);

        case TokenKind.String:
            return new StringLit(to!string(tk.value.s), tk.pos);

        case TokenKind.Identifier:
            expect(TokenKind.LParen, "Esperado '(' após o identificador.");
            string[] args;
            while (!isAtEnd() && !check(TokenKind.RParen))
            {
                args ~= to!string(expectId().value.s);
                if (!check(TokenKind.RParen))
                    expect(TokenKind.Comma, "Esperado ',' após o valor.");
            }
            expect(TokenKind.RParen, "Esperado ')' após a chamada.");
            return new CallExpr(to!string(tk.value.s), args, tk.pos);
        default:
            tk.print();
            err.error(tk.pos, "Esperado uma expressão válida.");
            err.report();
            hpy_validar(false, "Erro.");
            return Node.init; // retorna um valor default só pra não dar erro precoce
        }
    }

    Node parseStmt()
    {
        Token tk = advance();
        switch (tk.kind)
        {
        case TokenKind.Retorne:
            // ret $ID
            Token id = expectId();
            return instrRet(id, tk.pos);

        case TokenKind.Imediato:
            // ime T, $ID, VAL
            HType type = parseType();
            expectComma();

            Token id = expectId();
            checkType(type, context.tryGetVar(id).type, id.pos);
            expectComma();

            Node val = parseExpr();
            if (val.type !is null)
            {
                if (val.kind == NodeKind.IntLit || val.kind == NodeKind.CallExpr)
                    val.type = type;
                else
                    checkType(type, val.type, val.pos);
            }
            else
                val.type = type;

            context.setVarValue(id, val, true);
            return instrIme(type, id, val, tk.pos);

        case TokenKind.Aloca:
            // aloca T, $ID
            HType type = parseType();
            expectComma();

            Token id = expectId();
            if (!context.trySetVar(id, type))
                writeln("Erro ao adicionar variavel.");

            return instrAloca(type, id, tk.pos);

        case TokenKind.Soma:
            // soma T, $a, $b, $c
            HType type = parseType();
            expectComma();

            Token a = expectId();
            checkType(type, context.tryGetVar(a).type, a.pos);
            expectComma();

            Token b = expectId();
            checkType(type, context.tryGetVar(b).type, b.pos);
            expectComma();

            Token c = expectId();
            checkType(type, context.tryGetVar(c).type, c.pos);

            return instrSoma(type, a, b, c, tk.pos);

        case TokenKind.Chamada:
            // chamada T, CALLEXPR, $res
            HType type = parseType();
            expectComma();

            Node call = parseExpr();
            if (call.kind != NodeKind.CallExpr)
                err.error(call.pos, "Esperado uma chamada de função.");

            // checkType(type, context.tryGetVar(id).type, tk.pos);

            expectComma();
            Token res = expectId();
            checkType(type, context.tryGetVar(res).type, res.pos);

            context.setVarValue(res, call, false);
            return instrChamada(type, call, res, tk.pos);

        case TokenKind.Converter:
            // soma TF, TT, $a, $b
            HType from = parseType();
            expectComma();

            HType to = parseType();
            expectComma();

            Token a = expectId();
            checkType(from, context.tryGetVar(a).type, a.pos);
            expectComma();

            Token b = expectId();
            checkType(to, context.tryGetVar(b).type, b.pos);

            return instrConverter(from, to, a, b, tk.pos);

        default:
            err.error(tk.pos, "Esperado uma instrução válida.");
            err.report();
            hpy_validar(false, "Erro.");
            return Node.init;
        }
    }

    Node parseFnDecl(Position pos)
    {
        bool isExtern, isVariadic;
        HType retType = parseType();
        Token name = expect(TokenKind.Identifier, "Esperado um nome pra função.");
        context.setFn(name);
        expect(TokenKind.LParen, "Esperado um '(' após o nome da função.");
        FuncArg[] args;
        while (!isAtEnd() && !check(TokenKind.RParen))
        {
            if (match(TokenKind.Variadic))
            {
                isVariadic = true;
                break;
            }
            HType argType = parseType();
            Token argName = expect(TokenKind.Id, "Esperado um nome pro argumento.");
            context.trySetVar(argName, argType);
            args ~= new FuncArg(to!string(argName.value.s), argType);
            if (!check(TokenKind.RParen))
                expect(TokenKind.Comma, "Esperado ',' após o argumento.");
        }
        expect(TokenKind.RParen, "Esperado ')' após os argumentos da função.");
        Node[] body;
        if (match(TokenKind.SemiColon))
            isExtern = true;
        else
        {
            expect(TokenKind.LBrace, "Esperado '{' após a função.");
            while (!isAtEnd() && !check(TokenKind.RBrace))
                body ~= parseStmt();
            expect(TokenKind.RBrace, "Esperado '}' após o corpo da função.");
        }
        return new FuncDecl(to!string(name.value.s), retType, args, body, isExtern, isVariadic, pos);
    }

    Node parseDecl()
    {
        Token tk = advance();
        switch (tk.kind)
        {
        case TokenKind.Funcao:
            return parseFnDecl(tk.pos);
        default:
            err.error(tk.pos, "Esperado uma declaração válida.");
            return Node.init;
        }
    }

    HType parseType()
    {
        Token tk = expect(TokenKind.Identifier, "Esperado um identificador pro tipo.");
        string t = to!string(tk.value.s);

        HType* type = registry.getType(t);
        if (type is null)
        {
            err.error(tk.pos, "Esperado um tipo válido.");
            return HType.init;
        }

        return *type;
    }

public:
    this(Token[] tokens, Diagnostics err, TypeRegistry registry, Context context)
    {
        this.tokens = tokens;
        this.err = err;
        this.registry = registry;
        this.context = context;
    }

    Program parse()
    {
        Node[] body;
        while (!isAtEnd())
            body ~= parseDecl();
        return new Program(body);
    }
}
