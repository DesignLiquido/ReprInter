module frontend.parser.parser;

import std.format, std.stdio, std.conv, std.variant;
import frontend.lexer.token, frontend.parser.ast, frontend.type, erro;

enum Precedence
{
    LOWEST = 1,
    ASSIGN = 2, // =, +=, -=, |=, &=, <<=, >>=
    EQUALS = 3, // ==, !=
    OR = 4, // ||
    AND = 5, // &&
    BIT_OR = 6, // |
    BIT_XOR = 7, // ^
    BIT_AND = 8, // &
    SUM = 9, // +, -
    MUL = 10, // *, /
    BIT_SHIFT = 11, // <<, >>
    CALL = 12, // funções, index
    HIGHEST = 13,
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
        case TokenKind.Arroba:
            bool isArrba = false;
            if (token.kind == TokenKind.Dolar || token.kind == TokenKind.Arroba)
            {
                if (token.kind == TokenKind.Arroba)
                    isArrba = true;
                token = this.advance();
            }
            string id = isArrba ? "@" ~ token.value.get!string : token.value.get!string;
            if (this.check(TokenKind.LParen))
                return parseCallExpr(id, token.loc);
            if (this.match([TokenKind.Equals]))
            {
                Node value = this.parseExpression(Precedence.LOWEST);
                return new VarAssignmentDecl(id, value.type, value, token.loc);
            }
            Node operand = new Identifier(id, token.loc);
            if (this.match([TokenKind.PlusPlus, TokenKind.MinusMinus]))
                return new UnaryExpr(this.previous().value.get!string, operand, token.loc, true);
            if (this.match([TokenKind.Dot]))
                return this.parseMemberCallExpr(operand);
            if (this.match([TokenKind.LBracket]))
                return this.parseIndexExpr(operand);
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
            Node operand = new StringLiteral(token.value.get!string, token.loc);
            if (this.match([TokenKind.LBracket]))
                return this.parseIndexExpr(operand);
            return operand;
        case TokenKind.Alocar:
            return this.parseVarDecl();
        case TokenKind.Const:
            return this.parseConstDecl();
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
        case TokenKind.Enum:
            return this.parseEnumDecl();
        case TokenKind.Parar:
            return new BreakOrContinueStmt(true, token.loc);
        case TokenKind.Continuar:
            return new BreakOrContinueStmt(false, token.loc);
        case TokenKind.Enquanto:
            return this.parseWhileStmt();
        case TokenKind.Importar:
            return this.parseImportStmt();
        case TokenKind.LBracket:
            Node[] values;
            while (!this.check(TokenKind.RBracket) && !this.isAtEnd())
            {
                values ~= this.parseExpression(Precedence.LOWEST);
                this.match([TokenKind.Comma]);
            }
            Loc end = this.consume(TokenKind.RBracket, "Esperado ']' após a declaração do vetor.")
                .loc;
            end.end++;
            Type type = Type(Types.Array, BaseType.Any);
            return new ArrayLiteral(values, type, this.getLoc(token.loc, end));
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
            error.addError(Diagnostic("Token desconhecido: " ~ to!string(token.value), token.loc));
            throw new Exception("Token desconhecido: " ~ to!string(token.value));
        }
    }

    ImportStatement parseImportStmt()
    {
        bool[string] symbols = null;
        string aliasname = "";
        // Token file = this.consume(TokenKind.Txt, "Esperado o nome do arquivo.");
        Node file = this.parseExpression(Precedence.LOWEST);
        if (this.match([TokenKind.Colon]))
        {
            this.consume(TokenKind.LBrace, "Esperado '{' após ':'.");
            while (!this.check(TokenKind.RBrace) && !this.isAtEnd())
            {
                symbols[this.consume(TokenKind.Identifier, "Esperado um identificador dentro da importação seletiva.")
                    .value.get!string] = true;
                this.match([TokenKind.Comma]);
            }
            this.consume(TokenKind.RBrace, "Esperado '}' após a importação seletiva.");
        }
        if (this.match([TokenKind.Como]))
            aliasname = this.consume(TokenKind.Identifier,
                "Esperado um identificador após 'como' para o nome do alias.").value.get!string;

        return new ImportStatement(file, file.loc, symbols, aliasname);
    }

    ConstDeclaration parseConstDecl()
    {
        Node id = this.parseExpression(Precedence.HIGHEST);
        bool publico = this.match([TokenKind.Star]);
        if (id.kind != NodeKind.Identifier)
        {
            error.addError(Diagnostic("Era esperado um nome para a constante.", id.loc));
            throw new Exception("Era esperado um nome para a constante.");
        }
        Type ty = this.parseType();
        this.consume(TokenKind.Equals, "Esperado '=' após o tipo da constante.");
        Node value = this.parseExpression(Precedence.LOWEST);
        return new ConstDeclaration(id.value.get!string, ty, value, id.loc, publico);
    }

    WhileStatement parseWhileStmt()
    {
        Loc start = this.previous().loc;
        Node condition = this.parseExpression(Precedence.LOWEST);
        Node[] body = this.parseBody(true);
        return new WhileStatement(condition, body, start);
    }

    EnumDeclaration parseEnumDecl()
    {
        string name = this.consume(TokenKind.Identifier, "É esperado um nome para a enumeração.")
            .value.get!string;
        bool publico = this.match([TokenKind.Star]);
        Loc start = this.previous().loc;
        this.consume(TokenKind.LBrace, "Esperado '{' após o nome da enumeração.");
        EnumField[] fields;
        while (!this.check(TokenKind.RBrace) && !this.isAtEnd())
        {
            // nome = valor
            // nome
            string fieldName = this.consume(TokenKind.Identifier, "É esperado um nome para o campo.")
                .value.get!string;
            // int por padrão
            Node value = new IntLiteral(fields.length, this.previous().loc); // loc do fieldName
            bool dF = false;
            if (this.match([TokenKind.Equals]))
            {
                value = this.parseExpression(Precedence.LOWEST);
                dF = true;
            }
            // a validação só ocorrerá no analisador semantico
            value.type.enumName = name;
            fields ~= EnumField(fieldName, value.type, dF, value);
        }
        this.consume(TokenKind.RBrace, "Esperado '}' após a enumeração.");
        return new EnumDeclaration(name, fields, start, publico);
    }

    IndexAssignmentDecl parseIndexAssignmentDecl(IndexExpr member)
    {
        Node value = this.parseExpression(Precedence.LOWEST);
        return new IndexAssignmentDecl(member, value, member.loc);
    }

    Node parseIndexExpr(Node object)
    {
        // expr [ idx ] . || = || [
        // obect = expr
        Node idx = this.parseExpression(Precedence.LOWEST);
        this.consume(TokenKind.RBracket, "Esperado ']' após a obtenção de elemento por indice no vetor.");
        IndexExpr node = new IndexExpr(object, idx, object.loc);
        if (this.match([TokenKind.Equals]))
            return this.parseIndexAssignmentDecl(node);
        // encadeamento
        if (this.match([TokenKind.LBracket]))
            return this.parseIndexExpr(node);
        if (this.match([TokenKind.Dot]))
            return this.parseMemberCallExpr(node);
        return node;
    }

    MemberCallAssignmentDecl parseMemberCallAssignmentDecl(MemberCallExpr member)
    {
        Node value = this.parseExpression(Precedence.LOWEST);
        return new MemberCallAssignmentDecl(member, value, member.loc);
    }

    Node parseMemberCallExpr(Node object)
    {
        Identifier member;
        Token id = this.consume(TokenKind.Identifier, "O membro dessa expressão deve ser um identificador.");
        member = new Identifier(id.value.get!string, id.loc);
        Node[] args;
        bool isMethodCall = false;
        if (this.match([TokenKind.LParen]))
        {
            while (!this.check(TokenKind.RParen) && !this.isAtEnd())
            {
                args ~= this.parseExpression(Precedence.LOWEST);
                this.match([TokenKind.Comma]);
            }
            this.consume(TokenKind.RParen, "Esperava-se ')' após a chamada.");
            isMethodCall = true;
        }
        MemberCallExpr node = new MemberCallExpr(object, member, args, isMethodCall, object.loc);
        // se houver o '=' então é um Node diferente
        if (this.match([TokenKind.Equals]))
            return this.parseMemberCallAssignmentDecl(node);
        // encadeamento
        if (this.match([TokenKind.Dot]))
            return this.parseMemberCallExpr(node);
        if (this.match([TokenKind.LBracket]))
            return this.parseIndexExpr(node);
        if (this.match([TokenKind.PlusPlus, TokenKind.MinusMinus]))
            return new UnaryExpr(this.previous().value.get!string, node, node.loc, true);
        return node;
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
        bool publico = this.match([TokenKind.Star]);
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
        return new StructDeclaration(name, fields, start, publico);
    }

    ForStatement parseForStmt()
    {
        Loc start = previous().loc;
        Node init = this.parseExpression(Precedence.LOWEST); // alocar i int = 0
        this.consume(TokenKind.SemiColon, "Esperado ';' após a inicialização do 'para'.");
        Node condition = this.parseExpression(Precedence.LOWEST); // i < 1000
        this.consume(TokenKind.SemiColon, "Esperado ';' após a condição do 'para'.");
        Node increment = this.parseExpression(Precedence.LOWEST); // i++, ++i, --i, i--, i = i + 1, i += 1, ...
        Node[] body = this.parseBody(true); // { ... }
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

    Node parseCallExpr(string id, Loc start)
    {
        this.match([TokenKind.LParen]);
        Node[] args;
        while (!this.check(TokenKind.RParen) && !this.isAtEnd())
        {
            args ~= this.parseExpression(Precedence.LOWEST);
            this.match([TokenKind.Comma]);
        }
        this.consume(TokenKind.RParen, "Esperava-se ')' após a chamada.");
        CallExpr node = new CallExpr(id, args, start);
        if (this.match([TokenKind.Dot]))
            return this.parseMemberCallExpr(node);
        if (this.match([TokenKind.LBracket]))
            return this.parseIndexExpr(node);
        return node;
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
        bool publico = this.match([TokenKind.Star]);

        FunctionArgument[] args;
        if (this.match([TokenKind.LParen]))
        {
            args = parseFuncArgs();
            this.consume(TokenKind.RParen, "Esperado ')' após os argumentos da função.");
        }

        Type funcType = this.parseType();
        Node[] body;
        if (this.match([TokenKind.SemiColon]))
            return new FunctionDeclaration(id.value.get!string, args, body, funcType, id.loc, true, publico);

        body = this.parseBody();
        return new FunctionDeclaration(id.value.get!string, args, body, funcType, id.loc, false, publico);
    }

    FunctionArgument[] parseFuncArgs()
    {
        FunctionArgument[] args;
        while (this.peek().kind != TokenKind.RParen && !this.isAtEnd())
        {
            Node defaultValue = null;
            bool dV = false;
            bool isRef = false;
            if (this.match([TokenKind.Variadic]))
            {
                Type ty = Type(Types.Undefined, BaseType.Any, true);
                if (!this.check(TokenKind.Comma) && !this.check(TokenKind.RParen))
                {
                    ty = this.parseType();
                    ty.undefined = true;
                }
                args ~= FunctionArgument("...", ty, defaultValue, dV);
                break;
            }
            Token id = this.consume(TokenKind.Identifier, "Era esperado um nome para o argumento.");
            isRef = this.match([TokenKind.Ref]);
            Type ty = this.parseType();

            if (this.match([TokenKind.Equals]))
            {
                defaultValue = this.parseExpression(Precedence.LOWEST);
                dV = true;
            }

            args ~= FunctionArgument(id.value.get!string, ty, defaultValue, dV, isRef, id.loc);
            this.match([TokenKind.Comma]);
        }
        return args;
    }

    Node[] parseBody(bool uniqueStmt = false)
    {
        Node[] body_;
        if (!this.check(TokenKind.LBrace) && !uniqueStmt)
        {
            error.addError(Diagnostic("Esperava-se '{' para iniciar o corpo.", this.peek().loc));
            throw new Exception("Esperava-se '{' para iniciar o corpo.");
        }
        if (this.check(TokenKind.LBrace))
        {
            this.consume(TokenKind.LBrace, "Esperava-se '{' para iniciar o corpo.");
            while (!this.check(TokenKind.RBrace) && !this.isAtEnd())
                body_ ~= this.parseExpression(Precedence.LOWEST);
            this.consume(TokenKind.RBrace, "Esperava-se '{' depois do corpo.");
        }
        else
            body_ ~= this.parseExpression(Precedence.LOWEST);

        return body_;
    }

    Type parseType()
    {
        Token ty = this.advance();
        bool isArray = false;
        bool isQuali = false;
        Token quali;
        long dimensions = -1;
        Type* next_ = null; // ponteiro inicializado como null

        // |
        if (this.match([TokenKind.BitOr]))
        {
            // aloca memória para o próximo tipo e chama parseType recursivamente
            next_ = new Type();
            *next_ = this.parseType();
        }

        if (this.match([TokenKind.Dot]))
        {
            isQuali = true;
            quali = this.consume(TokenKind.Identifier, "Esperado um identificador no tipo qualificado.");
        }

        if (this.match([TokenKind.LBracket]))
        {
            isArray = true;
            if (!this.check(TokenKind.RBracket))
            {
                Token dim = this.consume(TokenKind.I64,
                    "Para especificar as dimensões do vetor é necessario passar um numero inteiro.");
                dimensions = dim.value.get!long;
            }
            this.consume(TokenKind.RBracket, "Esperado ']' durante a declaração do tipo de um vetor.");
        }

        if (isQuali)
            return Type(Types.Qualified, BaseType.Void, false, "", 0, "", next_, ty.value.get!string,
                quali.value.get!string);

        Type result;
        switch (ty.kind)
        {
        case TokenKind.Int:
        case TokenKind.I32:
        case TokenKind.I64:
            if (isArray)
                result = Type(Types.Array, BaseType.Int, false, "", dimensions, "", next_);
            else
                result = Type(Types.Literal, BaseType.Int, false, "", dimensions, "", next_);
            break;
        case TokenKind.Dec:
        case TokenKind.F64:
            if (isArray)
                result = Type(Types.Array, BaseType.Double, false, "", dimensions, "", next_);
            else
                result = Type(Types.Literal, BaseType.Double, false, "", dimensions, "", next_);
            break;
        case TokenKind.Txt:
            if (isArray)
                result = Type(Types.Array, BaseType.String, false, "", dimensions, "", next_);
            else
                result = Type(Types.Literal, BaseType.String, false, "", dimensions, "", next_);
            break;
        case TokenKind.Qualquer:
        case TokenKind.Qqr:
            if (isArray)
                result = Type(Types.Array, BaseType.Any, false, "", dimensions, "", next_);
            else
                result = Type(Types.Literal, BaseType.Any, false, "", dimensions, "", next_);
            break;
        case TokenKind.Logico:
            if (isArray)
                result = Type(Types.Array, BaseType.Bool, false, "", dimensions, "", next_);
            else
                result = Type(Types.Literal, BaseType.Bool, false, "", dimensions, "", next_);
            break;
        case TokenKind.Vazio:
            if (isArray)
                result = Type(Types.Array, BaseType.Void, false, "", dimensions, "", next_);
            else
                result = Type(Types.Void, BaseType.Void, false, "", dimensions, "", next_);
            break;
        default:
            if (isArray)
                result = Type(Types.Array, BaseType.Void, false, to!string(ty.value), dimensions, "", next_);
            else // pode ser struct ou enum
                result = Type(Types.Undefined, BaseType.Void, false, to!string(ty.value), dimensions,
                    to!string(ty.value), next_);
            break;
        }

        return result;
    }

    BinaryExpr parseBinaryExpr(Node left)
    {
        Token op = this.advance();
        Node right = this.parseExpression(this.getPrecedence(op.kind));
        return new BinaryExpr(left, right, op.value.get!string, this.getLoc(left.loc, right.loc));
    }

    // void infix(ref Node leftOld)
    // {
    //     switch (this.peek().kind)
    //     {
    //     case TokenKind.Plus:
    //     case TokenKind.Minus:
    //     case TokenKind.Star:
    //     case TokenKind.Slash:

    //     case TokenKind.And:
    //     case TokenKind.Or:

    //     case TokenKind.BitAnd:
    //     case TokenKind.BitOr:
    //     case TokenKind.BitXor:
    //     case TokenKind.BitSHL:
    //     case TokenKind.BitSHR:
    //     case TokenKind.BitSAR:

    //     case TokenKind.PlusEquals:
    //     case TokenKind.MinusEquals:
    //     case TokenKind.StarEquals:
    //     case TokenKind.SlashEquals:
    //     case TokenKind.ModuloEquals:

    //     case TokenKind.BitAndEquals:
    //     case TokenKind.BitOrEquals:
    //     case TokenKind.BitXorEquals:
    //     case TokenKind.BitSHLEquals:
    //     case TokenKind.BitSHREquals:

    //     case TokenKind.EqualsEquals:
    //     case TokenKind.GreaterThan:
    //     case TokenKind.GreaterThanEquals:
    //     case TokenKind.LessThanEquals:
    //     case TokenKind.LessThan:
    //     case TokenKind.NotEquals:
    //     case TokenKind.TildeEquals:
    //         leftOld = parseBinaryExpr(leftOld);
    //         return;
    //     default:
    //         return;
    //     }
    // }

    void infix(ref Node leftOld)
    {
        if (this.isBinaryOperator(this.peek().kind))
            leftOld = parseBinaryExpr(leftOld);
    }

    bool isBinaryOperator(TokenKind kind)
    {
        return this.getPrecedence(kind) > Precedence.LOWEST;
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
        case TokenKind.TildeEquals:
        case TokenKind.Or:
        case TokenKind.And:
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
