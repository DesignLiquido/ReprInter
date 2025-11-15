module middle.semantic_analyzer;

import std.stdio, std.format, std.conv, std.algorithm, std.array : array;
import frontend.type, frontend.parser.ast, erro, frontend.lexer.token : Loc;
import builtin;

struct Symbol
{
    Type type = Type.init;
    Node value = null; // para variáveis e valores padrão de argumentos
    bool isLet = true;
    bool isConst = false;
    bool isFunc = false;
    bool isStruct = false;
    bool isRef = false;
    bool isEnum = false;
    bool isPublic = false;
    string nameMangling = "main";
    Symbol[] funcArgs = [];
    StructField[] fields = []; // para estrutura
    EnumField[] eFields = []; // para enum
}

Symbol createFunction(Type type, Symbol[] args)
{
    return Symbol(type, null, false, true, true, false, false, false, false, "main", args);
}

Symbol[] createFunctionArgs(Type[] types)
{
    return types.map!(x => Symbol(x)).array;
}

class SemanticAnalyzer
{
private:
    Symbol[string][] scopes; // stack de escopos (cada escopo é um dicionário)
    Symbol[string] globalFuncs; // funções globais
    Symbol[string] structs; // estruturas
    Symbol[string] enums; // enums
    Symbol[string] consts; // consts
    Type currentFuncReturnType; // tipo de retorno da função atual
    bool insideFunction = false; // flag para verificar se estamos dentro de uma função
    bool insideLoop = false; // flag para verificar se estamos dentro de um loop
    DiagnosticError error;
    Builtin builtin;
    string nameMangling = "main";

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
        // busca em estruturas
        if (auto strct = name in structs)
            return strct;
        // busca em enums
        if (auto enm = name in enums)
            return enm;
        // busca em consts
        if (auto cnts = name in consts)
            return cnts;

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

    void checkType(ref Type left, ref Type right, ref Loc loc)
    {
        if (!left.isCompatibleWith(right, structs))
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
        case NodeKind.VarAssignmentDecl:
            return analyzeVarAssignment(cast(VarAssignmentDecl) node);
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
        case NodeKind.StructDeclaration:
            return analyzeStructDecl(cast(StructDeclaration) node);
        case NodeKind.Extern:
            return analyzeExtern(cast(Extern) node);
        case NodeKind.MemberCallExpr:
            return analyzeMemberCallExpr(cast(MemberCallExpr) node);
        case NodeKind.MemberCallAssignmentDecl:
            return analyzeMemberCallAssignmentDecl(cast(MemberCallAssignmentDecl) node);
        case NodeKind.ArrayLiteral:
            return analyzeArrayLiteral(cast(ArrayLiteral) node);
        case NodeKind.IndexExpr:
            return analyzeIndexExpr(cast(IndexExpr) node);
        case NodeKind.IndexAssignmentDecl:
            return analyzeIndexAssignmentDecl(cast(IndexAssignmentDecl) node);
        case NodeKind.EnumDeclaration:
            return analyzeEnumDecl(cast(EnumDeclaration) node);
        case NodeKind.BreakOrContinueStmt:
            if (!insideLoop)
                deErro(
                    "O 'parar' e o 'continuar' só podem ser usados dentro de loops.", node.loc);
            return node;
        case NodeKind.WhileStatement:
            return analyzeWhileStmt(cast(WhileStatement) node);
        case NodeKind.ConstDeclaration:
            return analyzeConstDecl(cast(ConstDeclaration) node);
            // literais não precisam de análise especial
        case NodeKind.IntLiteral:
        case NodeKind.DoubleLiteral:
        case NodeKind.BoolLiteral:
        case NodeKind.StringLiteral:
        case NodeKind.EoP:
        case NodeKind.ImportStatement:
            return node;

        default:
            deErro("Nó não suportado: " ~ to!string(node.kind), node.loc);
            return node;
        }
    }

    Node analyzeConstDecl(ConstDeclaration node)
    {
        return node;
    }

    Node analyzeWhileStmt(WhileStatement node)
    {
        node.condition = this.analyze(node.condition);
        this.insideLoop = true;
        foreach (ref Node n; node.body)
            n = this.analyze(n);
        // this.insideLoop = false;
        return node;
    }

    Node analyzeIndexAssignmentDecl(IndexAssignmentDecl node)
    {
        node.idxExpr = cast(IndexExpr) this.analyzeIndexExpr(node.idxExpr);
        node.value = this.analyze(node.value.get!Node);
        node.type = node.value.get!Node.type;
        return node;
    }

    Node analyzeIndexExpr(IndexExpr node)
    {
        node.idx = this.analyze(node.idx);
        node.object = this.analyze(node.object);
        node.type = node.object.type;
        if (node.object.type.baseType != BaseType.String && node.object.type.type != Types.Array)
            deErro(
                "O acesso ao indice só pode ser feito em vetores e dados do tipo texto.", node.loc);
        // se o meu object for uma estrutura o meu node terá esse tipo
        if (node.object.type.structName != "")
            node.type.type = Types.Struct;
        // TODO: melhorar isso
        if (node.object.type.type == Types.Array && node.object.type.structName == "")
            node.type.type = Types.Literal;
        return node;
    }

    Node analyzeArrayLiteral(ArrayLiteral node)
    {
        Node[] elements = node.value.get!(Node[]);
        if (elements.length > 0)
            foreach (ref elem; elements[0 .. $])
            {
                elem = analyze(elem);
                checkType(node.type, elem.type, elem.loc);
            }
        node.nameMangling = this.nameMangling;
        return node;
    }

    Node analyzeMemberCallAssignmentDecl(MemberCallAssignmentDecl node)
    {
        node.member = cast(MemberCallExpr) this.analyze(node.member);
        node.value = this.analyze(node.value.get!Node);
        node.nameMangling = this.nameMangling;
        return node;
    }

    Node analyzeMemberCallExpr(MemberCallExpr node)
    {
        // analisa o objeto à esquerda do ponto
        node.object = this.analyze(node.object);
        Node object = node.object;
        Node left = node.member;
        node.nameMangling = this.nameMangling;

        // o membro deve ser um identificador obrigatoriamente
        if (left.kind != NodeKind.Identifier)
            deErro("O membro da expressão deve ser um identificador.", object.loc);

        Identifier member = cast(Identifier) left;
        string campo = member.value.get!string;

        // tratamento para Enum
        if (object.type.type == Types.Enum)
        {
            Symbol* enumSym = this.lookupSymbol(object.type.enumName);

            if (enumSym is null)
                deErro(format("A enum '%s' não existe.", object.type.enumName), object.loc);
            if (!enumSym.isEnum)
                deErro(format("'%s' não é uma enum.", object.type.enumName), object.loc);

            EnumField[] enumFields = enumSym.eFields;
            long idx = -1;

            for (long i; i < enumFields.length; i++)
                if (enumFields[i].name == campo)
                {
                    idx = i;
                    break;
                }

            if (idx == -1)
                deErro(format("O campo '%s' não foi encontrado na enum '%s'.",
                        campo, object.type.enumName), member.loc);

            node.fieldIdx = idx;
            node.type = enumFields[idx].type;
            return node;
        }

        // tratamento para Struct
        if (object.type.type != Types.Struct)
            deErro("O tipo da expressão deve ser uma estrutura ou enum.", object.loc);

        Symbol* sym = this.lookupSymbol(object.type.structName);

        string nExiste = format("A estrutura '%s' não existe.", object.type.structName);
        if (sym is null)
            deErro(nExiste, object.loc);
        if (!sym.isStruct)
            deErro(nExiste, object.loc);

        StructField[] campos = sym.fields;
        long idx = -1;

        for (long i; i < campos.length; i++)
            if (campos[i].name == campo)
            {
                idx = i;
                break;
            }

        if (idx == -1)
            deErro(format("O campo '%s' não foi encontrado na estrutura '%s'.",
                    campo, object.type.structName), member.loc);

        node.fieldIdx = idx;
        node.type = campos[idx].type;
        return node;
    }

    Node analyzeExtern(Extern node)
    {
        foreach (FunctionDeclaration func; node.funcs)
        {
            if (func.name in globalFuncs)
                deErro(format("A função '%s' já existe.", func.name), func.loc);
            Symbol[] args = func.args.map!(x => Symbol(x.type, x.value)).array;
            globalFuncs[func.name] = createFunction(func.type, args);
        }
        return node;
    }

    Node analyzeEnumDecl(EnumDeclaration node)
    {
        return node;
    }

    Node analyzeStructDecl(StructDeclaration node)
    {
        return node;
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

        this.insideLoop = true;
        foreach (ref stmt; node.body)
            stmt = analyze(stmt);
        this.insideLoop = false;

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
        Symbol* sym_ = lookupSymbol(node.id);
        if (sym_ !is null)
            deErro(format("Variavel já existe '%s'", node.id), node.loc);

        if (node.value.convertsTo!Node)
        {
            Node valueNode = node.value.get!Node;
            valueNode = analyze(valueNode);
            checkType(node.type, valueNode.type, node.loc);
            node.value = valueNode;
            // não atualiza o tipo para evitar erros
            // se o checkType passou é porque ja é valido/compativel
            // não precisa alterar isso
            // node.type = valueNode.type;
        }

        Symbol sym;
        sym.type = node.type;
        sym.isLet = true;
        sym.isConst = false;
        sym.nameMangling = this.nameMangling;
        node.nameMangling = this.nameMangling;
        sym.value = node.value.get!Node;

        addSymbol(node.id, sym);
        return node;
    }

    Node analyzeVarAssignment(VarAssignmentDecl node)
    {
        Symbol* sym = lookupSymbol(node.id);
        if (sym is null)
            deErro(format("Variavel não existe '%s'", node.id), node.loc);

        if (sym.isConst)
            deErro(format("Não é possível redeclarar uma constante.", node.id), node.loc);

        if (node.value.convertsTo!Node)
        {
            Node valueNode = node.value.get!Node;
            valueNode = analyze(valueNode);
            checkType(sym.type, valueNode.type, node.loc);
            node.value = valueNode;
        }

        node.nameMangling = sym.nameMangling;
        node.type = sym.type;
        return node;
    }

    Node analyzeFuncDecl(FunctionDeclaration node)
    {
        // writeln("FN: ", node.name);
        // writeln("NM: ", node.nameMangling);
        // writeln("NMM: ", this.nameMangling);
        pushScope();
        scope (exit)
            popScope();

        bool variadic = false;

        foreach (ref param; node.args)
        {
            Symbol paramSym;
            paramSym.type = param.type;
            paramSym.isLet = true;
            paramSym.isConst = false;

            // variadic omg
            if (param.type.undefined)
                variadic = true;

            if (param.isRef)
            {
                if (param.type.type != Types.Struct && param.type.type != Types.Array)
                    deErro("Para receber um argumento com 'ref', o tipo deve ser uma estrutura ou vetor.", param
                            .loc);
                paramSym.isRef = param.isRef;
            }

            if (param.defaultValue)
                paramSym.value = param.value;

            addSymbol(param.name, paramSym);
        }

        if (variadic)
        {
            addSymbol("varargs", Symbol(Type(Types.Array, BaseType.Any)));
            addSymbol("varargc", Symbol(Type(Types.Literal, BaseType.Int)));
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

        foreach (ref stmt; node.body)
            stmt = analyze(stmt);

        return node;
    }

    Node analyzeStructExpr(CallExpr node, Symbol* symbol)
    {
        // recebe um callExpr e retorna uma structExpr
        ulong expectedArgsMin = 0;

        foreach (i, ref arg; symbol.fields)
            if (arg.value is null)
                expectedArgsMin++;

        // Verifica número mínimo de argumentos
        if (node.args.length < expectedArgsMin)
            deErro(format(
                    "A estrutura '%s' espera pelo menos %d campos, mas recebeu %d.",
                    node.id, expectedArgsMin, node.args.length
            ), node.loc);

        foreach (i, ref arg; node.args)
        {
            arg = analyze(arg);
            // verifica tipo do argumento correspondente
            if (i < symbol.fields.length)
                checkType(symbol.fields[i].type, arg.type, node.loc);
        }

        node.type = symbol.type;
        return new StructExpr(node);
    }

    Node analyzeCallExpr(CallExpr node)
    {
        Symbol* funcSym = lookupSymbol(node.id);
        if (funcSym is null || (!funcSym.isFunc && !funcSym.isStruct))
            deErro(format("A função '%s' não existe.", node.id), node.loc);

        if (funcSym.isStruct)
            return analyzeStructExpr(node, funcSym);

        ulong expectedArgsMin = 0;
        bool hasVariadic = false;
        long variadicIndex = 0;

        foreach (i, ref arg; funcSym.funcArgs)
        {
            if (arg.type.undefined)
            {
                hasVariadic = true;
                variadicIndex = i;
                break;
            }
            if (arg.value is null)
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
        node.nameMangling = funcSym.nameMangling; // atualiza o nameMangling pra chamar no codegen corretamente
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

        // writeln(node.value.get!string);
        // writeln("NM: ", node.nameMangling);
        // writeln("SYMNM: ", sym.nameMangling);
        // writeln("THISNM: ", this.nameMangling, "\n");

        if (sym.isStruct || sym.isEnum || sym.isConst)
            node.nameMangling = sym.nameMangling;
        else
            node.nameMangling = this.nameMangling;
        return node;
    }

    Node enumInitializer(EnumDeclaration node)
    {
        Symbol* sym = this.lookupSymbol(node.name);
        if (sym !is null)
            deErro(format("A enum ja existe '%s'.", node.name), node.loc);

        // valida os fields seguindo a seguinte regra
        // campo[0] define a regra de tipos
        EnumField[] fields = node.fields;
        if (fields.length > 0)
            for (long i; i < fields.length; i++)
                checkType(fields[0].type, fields[i].type, node.loc);

        Symbol symbol;
        symbol.type = node.type;
        symbol.eFields = fields;
        symbol.isEnum = true;
        symbol.isPublic = node.publico;
        symbol.nameMangling = this.nameMangling;
        structs[node.name] = symbol;
        return node;
    }

    Node structInitializer(StructDeclaration node)
    {
        Symbol* sym = this.lookupSymbol(node.name);
        if (sym !is null)
            deErro(format("A estrutura ja existe '%s'.", node.name), node.loc);
        Symbol symbol;
        symbol.type = node.type;
        symbol.fields = node.fields;
        symbol.isStruct = true;
        symbol.isPublic = node.publico;
        symbol.nameMangling = this.nameMangling;
        structs[node.name] = symbol;
        return node;
    }

    Node functionInitializer(FunctionDeclaration node)
    {
        // writeln("FUNC: ", node.name);
        // writeln("NM: ", node.nameMangling);
        // writeln("NM>: ", nameMangling);

        if (node.name in globalFuncs)
            deErro(format("A função '%s' já foi declarada.", node.name), node.loc);
        Symbol funcSym;
        funcSym.isFunc = true;
        funcSym.type = node.type;
        funcSym.isPublic = node.publico;
        funcSym.nameMangling = this.nameMangling;

        pushScope();
        scope (exit)
            popScope();

        foreach (ref param; node.args)
        {
            Symbol paramSym;
            paramSym.type = param.type;
            paramSym.isLet = true;
            paramSym.isConst = false;
            paramSym.nameMangling = this.nameMangling;

            if (param.isRef)
            {
                if (param.type.type != Types.Struct && param.type.type != Types.Array)
                    deErro("Para receber um argumento com 'ref', o tipo deve ser uma estrutura ou vetor.", param
                            .loc);
                paramSym.isRef = param.isRef;
            }

            if (param.defaultValue)
                paramSym.value = param.value;

            funcSym.funcArgs ~= paramSym;
        }
        globalFuncs[node.name] = funcSym;
        return node;
    }

    Node constInitializer(ConstDeclaration node)
    {
        Symbol* sym_ = lookupSymbol(node.id);
        if (sym_ !is null)
            deErro(format("Constante já existe '%s'", node.id), node.loc);

        if (node.value.convertsTo!Node)
        {
            Node valueNode = node.value.get!Node;
            valueNode = analyze(valueNode);
            checkType(node.type, valueNode.type, node.loc);
            node.value = valueNode;
        }

        Symbol sym;
        sym.type = node.type;
        sym.isLet = false;
        sym.isConst = true;
        sym.isPublic = node.publico;
        sym.value = node.value.get!Node;
        sym.nameMangling = this.nameMangling;
        consts[node.id] = sym;
        return node;
    }

    string getFileNameFromImport(Node node)
    {
        if (node.kind == NodeKind.StringLiteral || node.kind == NodeKind.Identifier)
            return node.value.get!string;

        if (node.kind == NodeKind.MemberCallExpr)
        {
            MemberCallExpr mce = cast(MemberCallExpr) node;
            return getFileNameFromImport(mce.object) ~ "/" ~ getFileNameFromImport(mce.member);
        }

        deErro("Expressão desconhecida.", node.loc);
        return "";
    }

    Node importInitializer(ImportStatement node)
    {
        import std.path : buildPath;

        string filename = getFileNameFromImport(node.value.get!Node);
        if (filename.length >= 4)
        {
            if (filename[$ - 3 .. $] != ".rp")
                filename ~= ".rp";
        }
        else
            filename ~= ".rp";
        string file = buildPath(node.loc.dir, filename);

        if (file in arquivosImportados)
            return node;
        import frontend.lexer.lexer, frontend.lexer.token, frontend.parser.parser;
        import std.file : readText, exists;
        import std.format : format;
        import std.algorithm : canFind;
        import env;

        // se não existir então vamos ver se é uma biblioteca padrão
        bool found = false;

        if (!exists(file))
        {
            // carrega as variaveis do ambiente
            loadEnv();
            // verifica pelo diretorio principal primeiro
            if (exists(MAIN_DIR ~ filename))
            {
                file = MAIN_DIR ~ filename; // se for biblioteca/entrada_saida.rp ele vira /home/<USR>/.harpy/...
                found = true;
            }
        }
        else
            found = true;

        if (!found)
            deErro(format("O arquivo não existe '%s'.", filename), node.loc);

        string fileContent = readText(file);
        Lexer lexer = new Lexer(file, fileContent, node.loc.dir, this.error);
        Token[] tokens = lexer.tokenize();
        Program program = new Parser(tokens, this.error).parse();
        SemanticAnalyzer analisador = new SemanticAnalyzer(this.error, builtin, file);
        analisador.analyze(program);

        // o programa analisado está lindo dimaizi
        // salva tudo em cache
        arquivosImportados[file] = program;

        // valida tudo e ja copia pro contexto atual
        if (node.symbols.length > 0)
            foreach (string name, bool val; node.symbols)
            {
                Symbol* sym = analisador.lookupSymbol(name);
                if (sym is null)
                    deErro(format("O simbolo '%s' não foi encontrado no arquivo '%'.", name, file), node
                            .loc);

                if (!sym.isPublic)
                    deErro(format("O simbolo '%s' não é publico para a importação.", name), node
                            .loc);

                if (sym.isConst)
                    consts[name] = *sym;
                else if (sym.isEnum)
                    enums[name] = *sym;
                else if (sym.isStruct)
                    structs[name] = *sym;
                else if (sym.isFunc)
                    globalFuncs[name] = *sym;
            }
        else
        {
            // adição manual de cada coisa
            foreach (string name, ref Symbol sym; analisador.consts)
                if (!sym.isPublic)
                    continue;
                else
                    consts[name] = sym;

            foreach (string name, ref Symbol sym; analisador.structs)
                if (!sym.isPublic)
                    continue;
                else
                    structs[name] = sym;

            foreach (string name, ref Symbol sym; analisador.enums)
                if (!sym.isPublic)
                    continue;
                else
                    enums[name] = sym;

            foreach (string name, ref Symbol sym; analisador.globalFuncs)
                if (!sym.isPublic)
                    continue;
                else
                    globalFuncs[name] = sym;
        }

        return node;
    }

public:
    Program[string] arquivosImportados; // cache das ASTs

    this(DiagnosticError error, ref Builtin embutido, string nameMangling = "main")
    {
        this.builtin = embutido;
        this.error = error;
        this.nameMangling = nameMangling;
    }

    void analyze(ref Program program)
    {
        pushScope();
        foreach (ref BuiltinFunction func; builtin.funcoes)
            globalFuncs[func.nome] = createFunction(func.retorno, createFunctionArgs(func.args));

        try
        {
            // cria as funções, estruturas, enums e constantes primeiro
            FunctionDeclaration[] funcoes = program.body
                .filter!(
                    node => node.kind == NodeKind.FuncDeclaration)
                .map!(node => cast(FunctionDeclaration) node)
                .array;

            StructDeclaration[] estruturas = program.body
                .filter!(
                    node => node.kind == NodeKind.StructDeclaration)
                .map!(node => cast(StructDeclaration) node)
                .array;

            EnumDeclaration[] enums_ = program.body
                .filter!(
                    node => node.kind == NodeKind.EnumDeclaration)
                .map!(node => cast(EnumDeclaration) node)
                .array;

            ConstDeclaration[] consts_ = program.body
                .filter!(
                    node => node.kind == NodeKind.ConstDeclaration)
                .map!(node => cast(ConstDeclaration) node)
                .array;

            ImportStatement[] imports = program.body
                .filter!(
                    node => node.kind == NodeKind.ImportStatement)
                .map!(node => cast(ImportStatement) node)
                .array;

            foreach (ImportStatement imprt; imports)
                importInitializer(imprt);

            foreach (FunctionDeclaration func; funcoes)
                functionInitializer(func);

            foreach (StructDeclaration strc; estruturas)
                structInitializer(strc);

            foreach (EnumDeclaration enm; enums_)
                enumInitializer(enm);

            foreach (ConstDeclaration const_; consts_)
                constInitializer(const_);

            foreach (ref stmt; program.body)
            {
                stmt.nameMangling = this.nameMangling; // atualiza o name_mangling da ast pro codegen lidar melhor
                stmt = analyze(stmt);
            }
        }
        finally
            popScope();
    }
}
