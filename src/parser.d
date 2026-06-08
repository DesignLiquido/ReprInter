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

    Token expectIdentifier()
    {
        return expect(TokenKind.Identifier, "Esperado um identificador.");
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

        case TokenKind.Obter:
        case TokenKind.Setar:
        case TokenKind.Soma:
            // obter | converter T, $a, $b, $c
            // soma T, $a, $b, $c
            bool cond = tk.kind == TokenKind.Setar || tk.kind == TokenKind.Obter;

            HType type = parseType();
            expectComma();

            Token a = expectId();
            checkType(type, context.tryGetVar(a).type, a.pos);
            expectComma();

            Token b = cond ? expectIdentifier() : expectId();
            if (!cond) checkType(type, context.tryGetVar(b).type, b.pos);
            expectComma();

            Token c = expectId();
            if (!cond) checkType(type, context.tryGetVar(c).type, c.pos);

            if (tk.kind == TokenKind.Obter)
                return instrObter(type, a, b, c, tk.pos);
            else if (tk.kind == TokenKind.Setar)
                return instrSetar(type, a, b, c, tk.pos);

            return instrSoma(type, a, b, c, tk.pos);

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

    Node parseStructDecl(Position pos)
    {
        Token name = expect(TokenKind.Identifier, "Esperado um nome para a estrutura.");
        string sName = to!string(name.value.s);

        if (registry.exists(sName))
        {
            err.error(name.pos, "A estrutura já existe.");
            return StructDecl.init;
        }

        expect(TokenKind.LBrace, "Esperado '{' após a estrutura.");
        
        // preciso calcular o tamanho da struct junto com os alinhamentos e tudo mais nesse exato momento
        StructField[] fields;
        StructField[string] tFields;
        uint structSize; // precisa alinhar ainda
        uint maxFieldSize; // o alinhamento deve ser feito com base no maior campo
        
        while (!isAtEnd() && !check(TokenKind.RBrace))
        {
            HType fType = parseType();
            uint fSize = fType.getSize();
            structSize += fSize;
            
            if (fSize > maxFieldSize)
                maxFieldSize = fSize;

            Token fName = expect(TokenKind.Identifier, "Esperado um home pro campo da estrutura.");
            fields ~= new StructField(to!string(fName.value.s), fType, fName.pos);
            
            if (!check(TokenKind.RBrace))
                expect(TokenKind.Comma, "Esperado ','.");
        }

        // normaliza em 8 no máximo
        if (maxFieldSize > 8)
            maxFieldSize = 8;

        // itera os fields dnv
        for (ulong i; i < fields.length; i++)
        {
            StructField field = fields[i];
            uint fSize = field.type.getSize();
            uint diff;
            // calcula o padding necessario inicialmente
            if (fSize < maxFieldSize)
            {
                diff = maxFieldSize - fSize;
                field.setPadding(diff);
            }

            // calcula o offset dessa bomba
            // teoricamente seria i * (fSize + diff)
            field.setOffset(i * (fSize + diff));

            if (field.name in tFields)
            {
                err.error(field.pos, "O campo já existe.");
                continue;
            }

            tFields[field.name] = field;
        }

        // o tamanho da struct deve ser alinhado na base do maxFieldSize
        structSize = alignUp(structSize, maxFieldSize);

        // cria e registra o tipo
        HTypeStruct type = new HTypeStruct(sName, tFields);
        type.size = structSize;
        registry.setType(sName, type);

        expect(TokenKind.RBrace, "Esperado '}' após o corpo da estrutura.");
        return new StructDecl(sName, fields, pos);
    }

    Node parseDecl()
    {
        Token tk = advance();
        switch (tk.kind)
        {
        case TokenKind.Funcao:
            return parseFnDecl(tk.pos);
        case TokenKind.Estrutura:
            return parseStructDecl(tk.pos);
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
