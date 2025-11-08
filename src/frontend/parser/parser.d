module frontend.parser.parser;

import std.format, std.stdio, std.conv, std.variant;
import frontend.lexer.token, frontend.parser.ast, frontend.type, erro;

enum Precedence
{
    LOWEST = 1,
    ASSIGN = 2, // =, +=, -=, |=, &=, <<=, >>=
    EQUALS = 3, // ==, !=
    BIT_OR = 4, // |
    BIT_XOR = 5, // ^
    BIT_AND = 6, // &
    SUM = 7, // +, -
    MUL = 8, // *, /
    BIT_SHIFT = 9, // <<, >>
    CALL = 10, // funções, index
    HIGHEST = 11,
}

class Parser
{
private:
    Token[] tokens;
    ulong pos = 0; // offset
    DiagnosticError error;

    Node parsePrefix()
    {
        Token token = this.advance();
        switch (token.kind)
        {
        case TokenKind.Identifier:
        case TokenKind.Dolar:
            if (token.kind == TokenKind.Dolar)
                token = this.advance();
            if (this.peek()
                .kind == TokenKind.LParen)
                return parseCallExpr(token.value.get!string, token.loc);
            if (this.peek().kind == TokenKind.Equals)
            {
                this.advance();
                Node value = this.parseExpression(Precedence.LOWEST);
                return new VarAssignmentDecl(token.value.get!string, value.type, value, token.loc);
            }
            Node operand = new Identifier(token.value.get!string, token.loc);
            if (this.check(TokenKind.PlusPlus) || this.check(TokenKind.MinusMinus))
            {
                Token postOp = this.advance();
                return new UnaryExpr(postOp.value.get!string, operand, token.loc, true);
            }
            return operand;
        case TokenKind.LParen:
            Node node = this.parseExpression(Precedence.LOWEST);
            this.consume(TokenKind.RParen, "Esperado ')' após a expressão.");
            return node;
        case TokenKind.I64:
            return new IntLiteral(to!long(token.value.get!string), token.loc);
        case TokenKind.F64:
            return new DoubleLiteral(to!double(token.value.get!string), token.loc);
        case TokenKind.Txt:
            return new StringLiteral(token.value.get!string, token.loc);
        case TokenKind.Alocar:
            return this.parseVarDecl();
        case TokenKind.Declarar:
            return this.parseFuncDecl();
        case TokenKind.Retorne:
            return this.parseReturn();
        case TokenKind.Para:
            return this.parseForStmt();
        case TokenKind.Se:
            return this.parseIfStatement();
        case TokenKind.Verdadeiro:
            return new BoolLiteral(true, token.loc);
        case TokenKind.Falso:
            return new BoolLiteral(false, token.loc);
        case TokenKind.Estrutura:
            return this.parseStructDecl();
        case TokenKind.Externo:
            return this.parseExtern();
        case TokenKind.Plus:
        case TokenKind.Minus:
        case TokenKind.PlusPlus:
        case TokenKind.MinusMinus:
        case TokenKind.Bang:
        case TokenKind.BitNot:
            Node operand = this.parseExpression(Precedence.HIGHEST);
            return new UnaryExpr(token.value.get!string, operand, token.loc, false);
        case TokenKind.Fim:
            return new EoP(token.loc);
        default:
            error.addError(Diagnostic("Token desconhecido: " ~ to!string(token), token.loc));
            throw new Exception("Token desconhecido: " ~ to!string(token));
        }
    }

    Extern parseExtern()
    {
        Loc start = this.previous().loc;

        this.consume(TokenKind.LBrace, "Esperado '{' após o externo.");
        Node node = Node.init; // eu iniciaria como 'null' porém receio que pode dar problemas no futuro
        FunctionDeclaration[] funcs;
        while (!this.check(TokenKind.RBrace) && !this.isAtEnd())
        {
            node = this.parseExpression(Precedence.LOWEST);
            if (node.kind != NodeKind.FuncDeclaration)
                throw new Exception(
                    "Não é permitido essa expressão dentro do corpo do externo: " ~ to!string(
                        node.kind));
            funcs ~= cast(FunctionDeclaration) node;
        }
        this.consume(TokenKind.RBrace, "Esperado '}' após o corpo do externo.");
        return new Extern(funcs, start);
    }

    StructDeclaration parseStructDecl()
    {
        string name = this.consume(TokenKind.Identifier, "É esperado um nome para a estrutura.")
            .value.get!string;
        Loc start = this.previous().loc;
        this.consume(TokenKind.LBrace, "Esperado '{' após o nome da estrutura.");
        StructField[] fields;
        while (!this.check(TokenKind.RBrace) && !this.isAtEnd())
        {
            // nome T
            string fieldName = this.consume(TokenKind.Identifier, "É esperado um nome para o campo.")
                .value.get!string;
            Type ty = this.parseType();
            Node value = null;
            bool dF = false;
            if (this.match([TokenKind.Equals]))
            {
                value = this.parseExpression(Precedence.LOWEST);
                dF = true;
            }
            fields ~= StructField(fieldName, ty, dF, value);
        }
        this.consume(TokenKind.RBrace, "Esperado '}' após a estrutura.");
        return new StructDeclaration(name, fields, start);
    }

    ForStatement parseForStmt()
    {
        Loc start = previous().loc;
        Node init = this.parseExpression(Precedence.LOWEST); // alocar i int = 0
        this.consume(TokenKind.SemiColon, "Esperado ';' após a inicialização do 'para'.");
        Node condition = this.parseExpression(Precedence.LOWEST); // i < 1000
        this.consume(TokenKind.SemiColon, "Esperado ';' após a condição do 'para'.");
        Node increment = this.parseExpression(Precedence.LOWEST); // i++, ++i, --i, i--, i = i + 1, i += 1, ...
        Node[] body = this.parseBody(); // { ... }
        return new ForStatement(init, condition, increment, body, start);
    }

    IfStatement parseIfStatement()
    {
        Loc start = this.previous().loc;
        Node condition = this.parseExpression(Precedence.LOWEST);
        Node[] body = this.parseBody(true);
        Node else_ = null;

        if (this.peek().kind == TokenKind.Senao)
        {
            Loc elseLoc = this.advance().loc;

            if (this.peek().kind == TokenKind.Se)
            {
                this.advance();
                Node ifStmt = this.parseIfStatement();
                else_ = ifStmt;
            }
            else
            {
                Node[] elseBody = this.parseBody(true);
                Node elseStmt = new ElseStatement(elseBody, Type(Types.Undefined, BaseType.Void), elseLoc);
                else_ = elseStmt;
            }
        }

        return new IfStatement(condition, body, Type(Types.Undefined, BaseType.Void), else_, start);
    }

    Return parseReturn()
    {
        Node n;
        if (this.match([TokenKind.SemiColon]))
            return new Return(n, false, this.previous().loc);
        n = this.parseExpression(Precedence.LOWEST);
        return new Return(n, true, n.loc);
    }

    CallExpr parseCallExpr(string id, Loc start)
    {
        this.match([TokenKind.LParen]);
        Node[] args;
        while (this.peek().kind != TokenKind.RParen && !this.isAtEnd())
        {
            args ~= this.parseExpression(Precedence.LOWEST);
            this.match([TokenKind.Comma]);
        }
        this.consume(TokenKind.RParen, "Esperava-se ')' após a chamada.");
        return new CallExpr(id, args, start);
    }

    VarDeclaration parseVarDecl()
    {
        Node id = this.parseExpression(Precedence.LOWEST);
        if (id.kind != NodeKind.Identifier)
        {
            error.addError(Diagnostic("Era esperado um nome para a variavel.", id.loc));
            throw new Exception("Era esperado um nome para a variavel.");
        }
        // Token id = this.consume(TokenKind.Identifier, "Era esperado um nome para a variavel.");
        Type ty = this.parseType();
        this.consume(TokenKind.Equals, "Esperado '=' após o tipo da variavel.");
        Node value = this.parseExpression(Precedence.LOWEST);
        return new VarDeclaration(id.value.get!string, ty, value, id.loc);
    }

    FunctionDeclaration parseFuncDecl()
    {
        Token id = this.consume(TokenKind.Identifier, "Era esperado um nome para a função.");

        FunctionArgument[] args;
        if (this.match([TokenKind.LParen]))
        {
            args = parseFuncArgs();
            this.consume(TokenKind.RParen, "Esperado ')' após os argumentos da função.");
        }

        Type funcType = this.parseType();
        Node[] body;
        if (this.match([TokenKind.SemiColon]))
            return new FunctionDeclaration(id.value.get!string, args, body, funcType, id.loc);

        body = this.parseBody();
        return new FunctionDeclaration(id.value.get!string, args, body, funcType, id.loc);
    }

    FunctionArgument[] parseFuncArgs()
    {
        FunctionArgument[] args;
        while (this.peek().kind != TokenKind.RParen && !this.isAtEnd())
        {
            Node defaultValue = null;
            bool dV = false;
            if (this.match([TokenKind.Variadic]))
            {
                args ~= FunctionArgument("...", Type(Types.Undefined, BaseType.Void, true), defaultValue, dV);
                break;
            }
            Token id = this.consume(TokenKind.Identifier, "Era esperado um nome para o argumento.");
            Type ty = this.parseType();

            if (this.match([TokenKind.Equals]))
            {
                defaultValue = this.parseExpression(Precedence.LOWEST);
                dV = true;
            }

            args ~= FunctionArgument(id.value.get!string, ty, defaultValue, dV, id.loc);
            this.match([TokenKind.Comma]);
        }
        return args;
    }

    Node[] parseBody(bool uniqueStmt = false)
    {
        Node[] body_;

        if (this.peek().kind != TokenKind.LBrace && !uniqueStmt)
        {
            error.addError(Diagnostic("Esperava-se '{' para iniciar o corpo.", this.peek().loc));
            throw new Exception("Esperava-se '{' para iniciar o corpo.");
        }

        if (this.peek().kind == TokenKind.LBrace)
        {
            this.consume(TokenKind.LBrace, "Esperava-se '{' para iniciar o corpo.");
            while (this.peek().kind != TokenKind.RBrace && !this.isAtEnd())
                body_ ~= this.parseExpression(Precedence.LOWEST);
            this.consume(TokenKind.RBrace, "Esperava-se '{' depois do corpo.");
        }
        else
            body_ ~= this.parseExpression(Precedence.LOWEST);

        return body_;
    }

    Type parseType()
    {
        // TODO: suportar arrays
        Token ty = this.advance();
        switch (ty.kind)
        {
        case TokenKind.Int:
        case TokenKind.I32:
        case TokenKind.I64:
            return Type(Types.Literal, BaseType.Int);
        case TokenKind.Dec:
        case TokenKind.F64:
            return Type(Types.Literal, BaseType.Double);
        case TokenKind.Txt:
            return Type(Types.Literal, BaseType.String);
        case TokenKind.Qualquer:
        case TokenKind.Qqr:
            return Type(Types.Literal, BaseType.Any);
        case TokenKind.Logico:
            return Type(Types.Literal, BaseType.Bool);
        case TokenKind.Vazio:
            return Type(Types.Void, BaseType.Void);
        default:
            return Type(Types.Struct, BaseType.Void, false, to!string(ty.value));
        }
    }

    BinaryExpr parseBinaryExpr(Node left)
    {
        Token op = this.advance();
        Node right = this.parseExpression(this.getPrecedence(op.kind));
        return new BinaryExpr(left, right, op.value.get!string, this.getLoc(left.loc, right.loc));
    }

    void infix(ref Node leftOld)
    {
        switch (this.peek().kind)
        {
        case TokenKind.Plus:
        case TokenKind.Minus:
        case TokenKind.Star:
        case TokenKind.Slash:

        case TokenKind.BitAnd:
        case TokenKind.BitOr:
        case TokenKind.BitXor:
        case TokenKind.BitSHL:
        case TokenKind.BitSHR:
        case TokenKind.BitSAR:

        case TokenKind.PlusEquals:
        case TokenKind.MinusEquals:
        case TokenKind.StarEquals:
        case TokenKind.SlashEquals:
        case TokenKind.ModuloEquals:

        case TokenKind.BitAndEquals:
        case TokenKind.BitOrEquals:
        case TokenKind.BitXorEquals:
        case TokenKind.BitSHLEquals:
        case TokenKind.BitSHREquals:

        case TokenKind.EqualsEquals:
        case TokenKind.GreaterThan:
        case TokenKind.GreaterThanEquals:
        case TokenKind.LessThanEquals:
        case TokenKind.LessThan:
        case TokenKind.NotEquals:
            leftOld = parseBinaryExpr(leftOld);
            return;
        default:
            return;
        }
    }

    Node parseExpression(Precedence precedence)
    {
        Node left = this.parsePrefix();
        while (!this.isAtEnd() && precedence < this.peekPrecedence())
        {
            ulong oldPos = this.pos;
            this.infix(left);
            if (this.pos == oldPos)
                break;
        }
        return left;
    }

    Node parseNode()
    {
        Node Node = this.parseExpression(Precedence.LOWEST);
        return Node;
    }

    pragma(inline, true);
    bool isAtEnd()
    {
        return this.peek().kind == TokenKind.Eof;
    }

    Variant next()
    {
        if (this.isAtEnd())
            return Variant(false);
        return Variant(this.tokens[this.pos + 1]);
    }

    pragma(inline, true);
    Token peek()
    {
        return this.tokens[this.pos];
    }

    pragma(inline, true);
    Token previous(ulong i = 1)
    {
        return this.tokens[this.pos - i];
    }

    Token advance()
    {
        if (!this.isAtEnd())
            this.pos++;
        return this.previous();
    }

    bool match(TokenKind[] kinds)
    {
        foreach (kind; kinds)
        {
            if (this.check(kind))
            {
                this.advance();
                return true;
            }
        }
        return false;
    }

    bool check(TokenKind kind)
    {
        if (this.isAtEnd())
            return false;
        return this.peek().kind == kind;
    }

    Token consume(TokenKind expected, string message)
    {
        if (this.check(expected))
            return this.advance();
        this.peek().print();
        error.addError(Diagnostic(format("Erro de parsing: %s", message), this.peek().loc));
        throw new Exception(format("Erro de parsing: %s", message));
    }

    Precedence getPrecedence(TokenKind kind)
    {
        switch (kind)
        {
        case TokenKind.Equals:
        case TokenKind.PlusEquals:
        case TokenKind.MinusEquals:
        case TokenKind.StarEquals:
        case TokenKind.SlashEquals:
        case TokenKind.ModuloEquals:
        case TokenKind.BitAndEquals:
        case TokenKind.BitOrEquals:
        case TokenKind.BitXorEquals:
        case TokenKind.BitSHLEquals:
        case TokenKind.BitSHREquals:
            return Precedence.ASSIGN;

        case TokenKind.EqualsEquals:
        case TokenKind.NotEquals:
        case TokenKind.GreaterThan:
        case TokenKind.LessThan:
        case TokenKind.LessThanEquals:
        case TokenKind.GreaterThanEquals:
            return Precedence.EQUALS;

        case TokenKind.BitOr:
            return Precedence.BIT_OR;
        case TokenKind.BitXor:
            return Precedence.BIT_XOR;
        case TokenKind.BitAnd:
            return Precedence.BIT_AND;

        case TokenKind.Plus:
        case TokenKind.Minus:
        case TokenKind.PlusPlus:
        case TokenKind.MinusMinus:
            return Precedence.SUM;
        case TokenKind.Star:
        case TokenKind.Slash:
        case TokenKind.Modulo:
            return Precedence.MUL;

        case TokenKind.BitSHL:
        case TokenKind.BitSHR:
        case TokenKind.BitSAR:
            return Precedence.BIT_SHIFT;

        case TokenKind.LParen:
        case TokenKind.LBracket:
            return Precedence.CALL;

        default:
            return Precedence.LOWEST;
        }
    }

    pragma(inline, true);
    Precedence peekPrecedence()
    {
        return this.getPrecedence(this.peek().kind);
    }

    pragma(inline, true);
    Loc getLoc(ref Loc start, ref Loc end)
    {
        return Loc(start.filename, start.dir, start.line, start.start, end.end);
    }

public:
    this(Token[] tokens = [], DiagnosticError error)
    {
        this.error = error;
        this.tokens = tokens;
    }

    Program parse()
    {
        Program program = new Program([]);
        try
        {
            while (!this.isAtEnd())
                program.body ~= this.parseNode();
            if (this.tokens.length == 0)
                return program;
        }
        catch (Exception e)
            throw e; // propaga
        return program;
    }
}
