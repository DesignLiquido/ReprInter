module middle.semantic_analyzer;

import std.stdio, std.format, std.conv, std.algorithm;
import frontend.type, frontend.parser.ast, erro, frontend.lexer.token : Loc;

private struct Symbol
{
    Type type = Type.init;
    Node value = Node.init; // para variáveis
    bool isLet = true;
    bool isConst = false;
    bool isFunc = false;
    Symbol[] funcArgs = [];
}

class SemanticAnalyzer
{
private:
    Symbol[string][] scopes; // stack de escopos (cada escopo é um dicionário)
    Symbol[string] globalFuncs; // funções globais
    Type currentFuncReturnType; // tipo de retorno da função atual
    bool insideFunction = false; // flag para verificar se estamos dentro de uma função
    DiagnosticError error;

    void pushScope()
    {
        scopes ~= (Symbol[string]).init;
    }

    void popScope()
    {
        if (scopes.length > 0)
            scopes = scopes[0 .. $ - 1];
        else
            throw new Exception("Attempt to remove non-existent scope");
    }

    Symbol* lookupSymbol(string name)
    {
        // busca em escopos locais
        for (long i = cast(long) scopes.length - 1; i >= 0; i--)
            if (auto sym = name in scopes[i])
                return sym;
        // busca em funções globais
        if (auto func = name in globalFuncs)
            return func;

        return null;
    }

    void addSymbol(string name, Symbol sym)
    {
        if (scopes.length == 0)
            throw new Exception("No active scope for adding symbol");
        if (name in scopes[$ - 1])
            throw new Exception(format("Symbol '%s' already declared in this scope", name));
        scopes[$ - 1][name] = sym;
    }

    pragma(inline, true);
    void deAviso(string message, Loc loc, Suggestion[] sugestoes = [])
    {
        error.addWarning(Diagnostic(message, loc, sugestoes));
    }

    void deErro(string message, Loc loc, Suggestion[] sugestoes = [])
    {
        error.addError(Diagnostic(message, loc, sugestoes));
        throw new Exception(message);
    }

    void checkType(Type left, Type right, ref Loc loc)
    {
        if (!left.isCompatibleWith(right))
            deErro(format(
                    "Tipo inesperado: esperado '%s', recebido '%s'",
                    left.toStr(), right.toStr()
            ), loc);
    }

    Node analyze(Node node)
    {
        if (node is null)
            return null;
        switch (node.kind)
        {
        case NodeKind.VarDeclaration:
            return analyzeVarDecl(cast(VarDeclaration) node);
        case NodeKind.FuncDeclaration:
            return analyzeFuncDecl(cast(FunctionDeclaration) node);
        case NodeKind.CallExpr:
            return analyzeCallExpr(cast(CallExpr) node);
        case NodeKind.BinaryExpr:
            return analyzeBinaryExpr(cast(BinaryExpr) node);
        case NodeKind.UnaryExpr:
            return analyzeUnaryExpr(cast(UnaryExpr) node);
        case NodeKind.Identifier:
            return analyzeIdentifier(cast(Identifier) node);
        case NodeKind.Return:
            return analyzeReturn(cast(Return) node);
        case NodeKind.IfStatement:
            return analyzeIfStmt(cast(IfStatement) node);
        case NodeKind.ElseStatement:
            return analyzeElseStmt(cast(ElseStatement) node);
        case NodeKind.ForStatement:
            return analyzeForStmt(cast(ForStatement) node);

            // literais não precisam de análise especial
        case NodeKind.IntLiteral:
        case NodeKind.DoubleLiteral:
        case NodeKind.BoolLiteral:
        case NodeKind.StringLiteral:
        case NodeKind.EoP:
            return node;

        default:
            deErro("Nó não suportado: " ~ to!string(node.kind), node.loc);
            return node;
        }
    }

    Node analyzeForStmt(ForStatement node)
    {
        pushScope();
        scope (exit)
            popScope();

        if (node.init_ !is null)
            node.init_ = analyze(node.init_);

        if (node.condition !is null)
        {
            node.condition = analyze(node.condition);
            if (node.condition.type.baseType != BaseType.Bool)
                deErro("A condição do 'para' deve ser do tipo lógico (boolean).", node.loc);
        }

        if (node.increment !is null)
            node.increment = analyze(node.increment);

        foreach (ref stmt; node.body)
            stmt = analyze(stmt);

        return node;
    }

    Node analyzeReturn(Return node)
    {
        if (!insideFunction)
            deErro("O 'retorne' foi usado fora de uma função.", node.loc);

        if (node.ret && node.value.convertsTo!Node)
        {
            Node returnValue = node.value.get!Node;
            returnValue = analyze(returnValue);
            node.value = returnValue;
            checkType(currentFuncReturnType, returnValue.type, node.loc);
        }
        else if (!node.ret && currentFuncReturnType.baseType != BaseType.Void)
            deErro("A função deve retornar um valor.", node.loc);

        return node;
    }

    Node analyzeIfStmt(IfStatement node)
    {
        node.condition = analyze(node.condition);
        if (node.condition.type.baseType != BaseType.Bool)
            deErro("A condição 'se' deve ser logica.", node.loc);

        pushScope();
        scope (exit)
            popScope();

        foreach (ref stmt; node.body)
            stmt = analyze(stmt);

        if (node.else_ !is null)
            node.else_ = analyze(node.else_);

        return node;
    }

    Node analyzeElseStmt(ElseStatement node)
    {
        pushScope();
        scope (exit)
            popScope();

        foreach (ref stmt; node.body)
            stmt = analyze(stmt);

        return node;
    }

    Node analyzeVarDecl(VarDeclaration node)
    {
        if (node.value.convertsTo!Node)
        {
            Node valueNode = node.value.get!Node;
            valueNode = analyze(valueNode);
            checkType(node.type, valueNode.type, node.loc);
            node.value = valueNode;
        }

        Symbol sym;
        sym.type = node.type;
        sym.isLet = true;
        sym.isConst = false;
        sym.value = node.value.get!Node;

        addSymbol(node.id, sym);
        return node;
    }

    Node analyzeFuncDecl(FunctionDeclaration node)
    {
        if (node.name in globalFuncs)
            deErro(format("A função '%s' já foi declarada.", node.name), node.loc);

        Symbol funcSym;
        funcSym.isFunc = true;
        funcSym.type = node.type;

        pushScope();
        scope (exit)
            popScope();

        foreach (param; node.args)
        {
            Symbol paramSym;
            paramSym.type = param.type;
            paramSym.isLet = true;
            paramSym.isConst = false;

            addSymbol(param.name, paramSym);
            funcSym.funcArgs ~= paramSym;
        }

        bool previousInsideFunction = insideFunction;
        Type previousReturnType = currentFuncReturnType;
        insideFunction = true;
        currentFuncReturnType = node.type;

        scope (exit)
        {
            insideFunction = previousInsideFunction;
            currentFuncReturnType = previousReturnType;
        }

        globalFuncs[node.name] = funcSym;

        foreach (ref stmt; node.body)
            stmt = analyze(stmt);

        return node;
    }

    Node analyzeCallExpr(CallExpr node)
    {
        Symbol* funcSym = lookupSymbol(node.id);
        if (funcSym is null || !funcSym.isFunc)
            deErro(format("A Função '%s' não existe.", node.id), node.loc);

        ulong expectedArgsMin = 0;
        bool hasVariadic = false;
        size_t variadicIndex = 0;

        foreach (i, ref arg; funcSym.funcArgs)
        {
            if (arg.type.toStr() == "undefined")
            {
                hasVariadic = true;
                variadicIndex = i;
                break;
            }
            expectedArgsMin++;
        }

        // Verifica número mínimo de argumentos
        if (node.args.length < expectedArgsMin)
            deErro(format(
                    "A função '%s' espera pelo menos %d argumentos, mas recebeu %d.",
                    node.id, expectedArgsMin, node.args.length
            ), node.loc);

        // Verifica número máximo se não for variadic
        if (!hasVariadic && node.args.length > funcSym.funcArgs.length)
            deErro(format(
                    "A função '%s' espera %d argumentos, mas recebeu %d.",
                    node.id, funcSym.funcArgs.length, node.args.length
            ), node.loc);

        foreach (i, ref arg; node.args)
        {
            arg = analyze(arg);
            // se passou do último argumento definido e tem variadic, aceita qualquer tipo
            if (hasVariadic && i >= variadicIndex)
                continue;
            // verifica tipo do argumento correspondente
            if (i < funcSym.funcArgs.length)
                checkType(funcSym.funcArgs[i].type, arg.type, node.loc);
        }

        node.type = funcSym.type;
        return node;
    }

    Node analyzeBinaryExpr(BinaryExpr node)
    {
        node.left = analyze(node.left);
        node.right = analyze(node.right);

        if (node.op == "==" || node.op == "!=" || node.op == "!=" || node.op == "<" ||
            node.op == ">" || node.op == "<=" || node.op == ">=")
        {
            node.type = Type(Types.Literal, BaseType.Bool);
            return node;
        }

        if (node.op == "&&" || node.op == "||")
        {
            if (node.left.type.baseType != BaseType.Bool || node.right.type.baseType != BaseType
                .Bool)
                deErro("Os operadores lógicos requerem operandos lógicos.", node.loc);
            node.type = Type(Types.Literal, BaseType.Bool);
            return node;
        }

        checkType(node.left.type, node.right.type, node.loc);
        node.type = node.left.type;
        return node;
    }

    Node analyzeUnaryExpr(UnaryExpr node)
    {
        node.operand = analyze(node.operand);

        if (node.op == "!")
        {
            if (node.operand.type.baseType != BaseType.Bool)
                deErro("O operador '!' requer um operando booleano.", node.loc);
            node.type = Type(Types.Literal, BaseType.Bool);
        }
        else if (node.op == "++" || node.op == "--" || node.op == "-" || node.op == "+")
        {
            if (!node.operand.type.isNumeric())
                deErro(format("O operador '%s' requer um operando numérico.", node.op), node.loc);
            node.type = node.operand.type;
        }
        else if (node.op == "~")
        {
            if (!node.operand.type.isNumeric() || node.operand.type.toStr() != "inteiro")
                deErro(format("O operador '%s' requer um operando numérico.", node.op), node.loc);
            node.type = node.operand.type;
        }

        return node;
    }

    Node analyzeIdentifier(Identifier node)
    {
        Symbol* sym = lookupSymbol(node.value.get!string);
        if (sym is null)
            deErro(format("Identificador '%s' não declarado.", node.value.get!string), node.loc);

        node.type = sym.type;
        return node;
    }

public:
    this(DiagnosticError error)
    {
        this.error = error;
    }

    void analyze(ref Program program)
    {
        pushScope();
        globalFuncs["__nucleo_harpy_escreva"] = Symbol(Type(Types.Void, BaseType.Void), Node.init, false, true, true,
            [Symbol(Type(Types.Undefined, BaseType.Void))]);
        try
            foreach (ref stmt; program.body)
                stmt = analyze(stmt);
                finally
                    popScope();
    }
}
