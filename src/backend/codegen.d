module backend.codegen;

import std.stdio, std.format, std.conv, std.algorithm, std.string, std.array : array;
import core.sys.posix.dlfcn;
import frontend.parser.ast, frontend.type, frontend.lexer.token : Loc;
import backend.harpyvm, erro;

class CodeGen
{
private:
    DiagnosticError error;
    HarpyVM engine;
    HarpyCG cg;
    string[] externLibs;
    bool halt = false;
    LoopContext[] loopStack;

    struct FunctionArg
    {
        string name;
        bool defaultValue = false;
        bool isRef = false;
        Node value = null;
    }

    struct FunctionContext
    {
        string name;
        string[] params;
        int localVarCount;
    }

    struct LoopContext
    {
        string continueLabel;
        string breakLabel;
        int[] breakPatches; // índices para patch
        int[] continuePatches; // índices para patch
    }

    // toda função declara isso para controlar as chamadas de funções
    FunctionArg[][string] functionArguments;

    FunctionContext[] funcContextStack;
    int labelCounter = 0;

    struct VarInfo
    {
        bool isGlobal;
        string name;
    }

    VarInfo[string][] scopeStack;

    struct ExternFunc
    {
        string name;
        string library;
        void* handle;
    }

    ExternFunc[string] externFuncs;

    string genLabel(string prefix = "L")
    {
        return format("%s%d", prefix, labelCounter++);
    }

    void pushScope()
    {
        scopeStack ~= (VarInfo[string]).init;
    }

    void popScope()
    {
        if (scopeStack.length > 0)
            scopeStack = scopeStack[0 .. $ - 1];
    }

    void addVar(string name, bool isGlobal)
    {
        if (scopeStack.length == 0)
            throw new Exception("No active scope");

        VarInfo info;
        info.isGlobal = isGlobal;
        info.name = name;
        scopeStack[$ - 1][name] = info;
    }

    VarInfo* lookupVar(string name)
    {
        // Busca do escopo mais interno para o mais externo
        for (long i = cast(long) scopeStack.length - 1; i >= 0; i--)
        {
            if (auto var = name in scopeStack[i])
                return var;
        }
        return null;
    }

    pragma(inline, true);
    bool isInGlobalScope()
    {
        return funcContextStack.length == 0;
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

    Value makeValue(Node node)
    {
        switch (node.kind)
        {
        case NodeKind.IntLiteral:
            return engine.makeInt(node.value.get!long);
        case NodeKind.DoubleLiteral:
            return engine.makeFloat(node.value.get!double);
        case NodeKind.StringLiteral:
            return engine.makeStr(node.value.get!string);
        case NodeKind.BoolLiteral:
            return engine.makeBool(node.value.get!bool);
        default:
            deErro(format("Literal desconhecido: %s", node.kind), node.loc);
            throw new Exception("");
        }
    }

public:
    void*[string] libs;
    ffi_extern_function[string] externalFunctions;

    this(HarpyVM engine, DiagnosticError error, ref void*[string] libs)
    {
        this.engine = engine;
        this.libs = libs;
        this.cg = new HarpyCG(engine);
        this.error = error;
        pushScope();
    }

    Instruction[] generate(Program program)
    {
        FunctionDeclaration[] funcoes = program.body
            .filter!(
                node => node.kind == NodeKind.FuncDeclaration)
            .map!(node => cast(FunctionDeclaration) node)
            .array;

        foreach (FunctionDeclaration func; funcoes)
            functionInitializer(func);

        cg.label("main");

        foreach (stmt; program.body)
            generateNode(stmt);

        if (!halt)
            cg.emit(Instruction(OpCode.HALT));
        popScope();
        cg.callLabel("principal");
        return cg.build();
    }

    void generateNode(Node node)
    {
        if (node is null)
            return;

        switch (node.kind)
        {
        case NodeKind.VarDeclaration:
            generateVarDecl(cast(VarDeclaration) node);
            break;
        case NodeKind.VarAssignmentDecl:
            generateVarAssignment(cast(VarAssignmentDecl) node);
            break;
        case NodeKind.FuncDeclaration:
            generateFuncDecl(cast(FunctionDeclaration) node);
            break;
        case NodeKind.CallExpr:
            generateCallExpr(cast(CallExpr) node);
            break;
        case NodeKind.BinaryExpr:
            generateBinaryExpr(cast(BinaryExpr) node);
            break;
        case NodeKind.UnaryExpr:
            generateUnaryExpr(cast(UnaryExpr) node);
            break;
        case NodeKind.Identifier:
            generateIdentifier(cast(Identifier) node);
            break;
        case NodeKind.IfStatement:
            generateIfStmt(cast(IfStatement) node);
            break;
        case NodeKind.Return:
            generateReturn(cast(Return) node);
            break;
        case NodeKind.ForStatement:
            generateForStmt(cast(ForStatement) node);
            break;
        case NodeKind.IntLiteral:
        case NodeKind.DoubleLiteral:
        case NodeKind.StringLiteral:
        case NodeKind.BoolLiteral:
            generateLiteral(node);
            break;
        case NodeKind.StructDeclaration:
            // ignora, tecnicamente esse Node só existe para validar a geração de structs com StructExpr
            break;
        case NodeKind.StructExpr:
            generateStructExpr(cast(StructExpr) node);
            break;
        case NodeKind.MemberCallExpr:
            generateMemberCallExpr(cast(MemberCallExpr) node);
            break;
        case NodeKind.MemberCallAssignmentDecl:
            generateMemberCallAssignmentDecl(cast(MemberCallAssignmentDecl) node);
            break;
        case NodeKind.Extern:
            generateExtern(cast(Extern) node);
            break;
        case NodeKind.ArrayLiteral:
            generateArrayLiteral(cast(ArrayLiteral) node);
            break;
        case NodeKind.IndexExpr:
            generateIndexExpr(cast(IndexExpr) node);
            break;
        case NodeKind.IndexAssignmentDecl:
            generateIndexAssignmentDecl(cast(IndexAssignmentDecl) node);
            break;
        case NodeKind.EnumDeclaration:
            EnumDeclaration e = cast(EnumDeclaration) node;
            for (long i = cast(long) e.fields.length - 1; i >= 0; i--)
                generateNode(e.fields[i].value);
            cg.emit(Instruction(OpCode.ENUMN, engine.makeInt(e.fields.length)));
            cg.emit(Instruction(OpCode.STOREG, engine.makeStr(e.name)));
            this.addVar(e.name, true);
            break;
        case NodeKind.BreakOrContinueStmt:
            generateBreakOrContinue(cast(BreakOrContinueStmt) node);
            break;
        case NodeKind.WhileStatement:
            generateWhileStmt(cast(WhileStatement) node);
            break;
        case NodeKind.EoP:
            halt = true;
            cg.emit(Instruction(OpCode.HALT));
            break;
        default:
            deErro(format("Geração de código não implementada para: %s", node.kind), node.loc);
            break;
        }
    }

    void generateWhileStmt(WhileStatement node)
    {
        pushScope();

        string loopLabel = genLabel("loop");
        string continueLabel = genLabel("continue");
        string endLabel = genLabel("end_loop");

        LoopContext loopCtx;
        loopCtx.continueLabel = continueLabel;
        loopCtx.breakLabel = endLabel;

        loopStack ~= loopCtx;
        scope (exit)
            loopStack = loopStack[0 .. $ - 1];

        cg.label(loopLabel);

        generateNode(node.condition);
        cg.emit(Instruction(OpCode.JZ, engine.makeInt(-1)));
        int jzIdx = cast(int) cg.program.length - 1;

        foreach (stmt; node.body)
            generateNode(stmt);

        cg.label(continueLabel);

        foreach (patchIdx; loopStack[$ - 1].continuePatches)
            cg.program[patchIdx].val = engine.makeInt(cast(long) cg.labels[continueLabel]);

        cg.emit(Instruction(OpCode.JMP, engine.makeInt(cast(long) cg.labels[loopLabel])));
        cg.label(endLabel);

        cg.program[jzIdx].val = engine.makeInt(cast(long) cg.labels[endLabel]);

        foreach (patchIdx; loopStack[$ - 1].breakPatches)
            cg.program[patchIdx].val = engine.makeInt(cast(long) cg.labels[endLabel]);

        popScope();
    }

    // void generateIndexAssignmentDecl(IndexAssignmentDecl node)
    // {
    //     generateNode(node.idxExpr.object); // faz o push do array
    //     generateNode(node.idxExpr.idx); // push do idx
    //     generateNode(node.value.get!Node); // push do valor
    //     cg.emit(Instruction(OpCode.ARRS));
    // }
    void generateIndexAssignmentDecl(IndexAssignmentDecl node)
    {
        if (node.idxExpr.object.kind == NodeKind.Identifier)
        {
            Identifier id = cast(Identifier) node.idxExpr.object;
            string varName = id.value.get!string;
            VarInfo* varInfo = lookupVar(varName);

            if (varInfo is null)
                deErro(format("Variável não encontrada: %s", varName), node.loc);

            // Carrega o array
            if (varInfo.isGlobal)
                cg.emit(Instruction(OpCode.LOADG, engine.makeStr(varName)));
            else
                cg.loadLocal(varName);

            generateNode(node.idxExpr.idx); // push do índice
            generateNode(node.value.get!Node); // push do valor
            cg.emit(Instruction(OpCode.ARRS));

            // Salva de volta
            if (varInfo.isGlobal)
                cg.emit(Instruction(OpCode.STOREG, engine.makeStr(varName)));
            else
                cg.storeLocal(varName);
        }
        else
        {
            generateNode(node.idxExpr.object);
            generateNode(node.idxExpr.idx);
            generateNode(node.value.get!Node);
            cg.emit(Instruction(OpCode.ARRS));
        }
    }

    void generateIndexExpr(IndexExpr node)
    {
        generateNode(node.object); // faz o push do array
        generateNode(node.idx); // push do idx
        if (node.type.baseType == BaseType.String)
            cg.emit(Instruction(OpCode.STRG));
        else
            cg.emit(Instruction(OpCode.ARRG));
    }

    void generateArrayLiteral(ArrayLiteral node)
    {
        Node[] elements = node.value.get!(Node[]);
        foreach_reverse (elem; elements)
            generateNode(elem);
        // não é o tamanho que será alocado, é apenas a quantidade de valores que foram colocados na stack
        cg.push(engine.makeInt(cast(long) elements.length));
        cg.emit(Instruction(OpCode.ARRN));
    }

    // void generateMemberCallAssignmentDecl(MemberCallAssignmentDecl node)
    // {
    //     // gera o memberCallExpr
    //     // sendo uma estrutura haverá um push dela para a stack
    //     // como não queremos isso e só queremos a struct nós geramos o object dela apenas
    //     generateNode(node.member.object);
    //     // e agora só gerar o set
    //     // faz o push do novo valor para a stack e altera com OpCode.STRUCTS
    //     generateNode(node.value.get!Node);
    //     cg.emit(Instruction(OpCode.STRUCTS, engine.makeInt(cast(long) node.member.fieldIdx)));
    //     // sim é só isso
    // }

    void generateMemberCallAssignmentDecl(MemberCallAssignmentDecl node)
    {
        // Se o object é um Identifier, precisamos recarregar e salvar
        if (node.member.object.kind == NodeKind.Identifier)
        {
            Identifier id = cast(Identifier) node.member.object;
            string varName = id.value.get!string;
            VarInfo* varInfo = lookupVar(varName);

            if (varInfo is null)
                deErro(format("Variável não encontrada: %s", varName), node.loc);

            // Carrega a struct
            if (varInfo.isGlobal)
                cg.emit(Instruction(OpCode.LOADG, engine.makeStr(varName)));
            else
                cg.loadLocal(varName);

            // Push do novo valor
            generateNode(node.value.get!Node);

            // Modifica o field
            cg.emit(Instruction(OpCode.STRUCTS, engine.makeInt(cast(long) node.member.fieldIdx)));

            // Salva de volta
            if (varInfo.isGlobal)
                cg.emit(Instruction(OpCode.STOREG, engine.makeStr(varName)));
            else
                cg.storeLocal(varName);
        }
        else
        {
            // Para casos mais complexos (struct aninhada, etc)
            generateNode(node.member.object);
            generateNode(node.value.get!Node);
            cg.emit(Instruction(OpCode.STRUCTS, engine.makeInt(cast(long) node.member.fieldIdx)));
        }
    }

    void generateMemberCallExpr(MemberCallExpr node, bool multi = false)
    {
        // gera o object
        // sendo uma estrutura haverá um push dela para a stack
        //node.object.print();
        generateNode(node.object);
        if (multi)
            generateNode(node.object);
        // e agora só gerar o get que ele fará o push do valor diretamente para a stack
        if (node.object.type.type == Types.Struct)
            cg.emit(Instruction(OpCode.STRUCTG, engine.makeInt(cast(long) node.fieldIdx)));
        else
            cg.emit(Instruction(OpCode.ENUMG, engine.makeInt(cast(long) node.fieldIdx)));
        // sim é só isso
    }

    version (linux)
    {
        void generateExtern(Extern node)
        {
            foreach (FunctionDeclaration funcDecl; node.funcs)
            {
                string name = funcDecl.name;

                if (name in externFuncs)
                    return;

                void* foundHandle = null;
                string foundLib = null;

                foreach (string lib, void* handle; libs)
                {
                    auto funcPtr = cast(ffi_extern_function) dlsym(handle, name.toStringz);
                    if (funcPtr !is null)
                    {
                        externalFunctions[name] = funcPtr;
                        foundHandle = handle;
                        foundLib = lib;
                        break;
                    }
                }

                if (foundLib is null)
                    deErro(format("Simbolo '%s' não foi encontrado.", name), node.loc);

                FunctionArg[] args;
                foreach (arg; funcDecl.args)
                    args ~= FunctionArg(arg.name, arg.defaultValue, arg.isRef, arg.value);
                functionArguments[name] = args;

                externFuncs[name] = ExternFunc(name, foundLib, foundHandle);
            }
        }
    }
    else version (Windows)
    {
        // preciso implementar uma versão especifica pro windows ainda
        void generateExtern(Extern node)
        {
            throw new Exception("O Windows não suporta o uso de 'externo' no momento.");
        }
    }
    else
    {
        void generateExtern(Extern node)
        {
            throw new Exception(
                "Seu sistema operacional não suporta o uso de 'externo' no momento.");
        }
    }

    void generateStructExpr(StructExpr node)
    {
        // cria a struct e seta os valores em cada field
        foreach_reverse (Node field; node.fields)
            generateNode(field);
        cg.emit(Instruction(OpCode.STRUCTN, engine.makeInt(node.fields.length)));
        // sim, é só isso
    }

    void generateForStmt(ForStatement node)
    {
        pushScope();

        string loopLabel = genLabel("loop");
        string continueLabel = genLabel("continue");
        string endLabel = genLabel("end_loop");

        LoopContext loopCtx;
        loopCtx.continueLabel = continueLabel;
        loopCtx.breakLabel = endLabel;

        loopStack ~= loopCtx;
        scope (exit)
            loopStack = loopStack[0 .. $ - 1];

        if (node.init_ !is null)
            generateNode(node.init_);

        cg.label(loopLabel);

        if (node.condition !is null)
        {
            generateNode(node.condition);
            cg.emit(Instruction(OpCode.JZ, engine.makeInt(-1)));
            int jzIdx = cast(int) cg.program.length - 1;

            foreach (stmt; node.body)
                generateNode(stmt);

            cg.label(continueLabel);

            foreach (patchIdx; loopStack[$ - 1].continuePatches)
                cg.program[patchIdx].val = engine.makeInt(cast(long) cg.labels[continueLabel]);

            if (node.increment !is null)
                generateNode(node.increment);

            cg.emit(Instruction(OpCode.JMP, engine.makeInt(cast(long) cg.labels[loopLabel])));
            cg.label(endLabel);

            cg.program[jzIdx].val = engine.makeInt(cast(long) cg.labels[endLabel]);

            foreach (patchIdx; loopStack[$ - 1].breakPatches)
                cg.program[patchIdx].val = engine.makeInt(cast(long) cg.labels[endLabel]);
        }
        else
        {
            foreach (stmt; node.body)
                generateNode(stmt);

            cg.label(continueLabel);
            foreach (patchIdx; loopStack[$ - 1].continuePatches)
                cg.program[patchIdx].val = engine.makeInt(cast(long) cg.labels[continueLabel]);

            if (node.increment !is null)
                generateNode(node.increment);

            cg.emit(Instruction(OpCode.JMP, engine.makeInt(cast(long) cg.labels[loopLabel])));
            cg.label(endLabel);

            foreach (patchIdx; loopStack[$ - 1].breakPatches)
                cg.program[patchIdx].val = engine.makeInt(cast(long) cg.labels[endLabel]);
        }

        popScope();
    }

    void generateBreakOrContinue(BreakOrContinueStmt node)
    {
        if (loopStack.length == 0)
            deErro(format("'%s' deve ser usado dentro de um loop.",
                    node.isBreak ? "parar" : "continuar"), node.loc);

        cg.emit(Instruction(OpCode.JMP, engine.makeInt(-1)));
        int jmpIdx = cast(int) cg.program.length - 1;

        if (node.isBreak)
            loopStack[$ - 1].breakPatches ~= jmpIdx;
        else
            loopStack[$ - 1].continuePatches ~= jmpIdx;
    }

    void generateReturn(Return node)
    {
        if (node.ret && node.value.convertsTo!Node)
        {
            Node returnValue = node.value.get!Node;
            generateNode(returnValue);
        }
        cg.emit(Instruction(OpCode.RET));
    }

    void generateIfStmt(IfStatement node)
    {
        string elseLabel = genLabel("else");
        string endLabel = genLabel("end_if");

        generateNode(node.condition);

        // Jump se falso
        cg.emit(Instruction(OpCode.JZ, engine.makeInt(-1)));
        int jzIdx = cast(int) cg.program.length - 1;

        pushScope();
        foreach (stmt; node.body)
            generateNode(stmt);
        popScope();

        if (node.else_ !is null)
        {
            cg.emit(Instruction(OpCode.JMP, engine.makeInt(-1)));
            int jmpIdx = cast(int) cg.program.length - 1;

            cg.label(elseLabel);
            cg.program[jzIdx].val = engine.makeInt(cast(long) cg.program.length);

            if (node.else_.kind == NodeKind.ElseStatement)
            {
                ElseStatement elseStmt = cast(ElseStatement) node.else_;
                pushScope();
                foreach (stmt; elseStmt.body)
                    generateNode(stmt);
                popScope();
            }
            else if (node.else_.kind == NodeKind.IfStatement)
                generateIfStmt(cast(IfStatement) node.else_);

            cg.label(endLabel);
            cg.program[jmpIdx].val = engine.makeInt(cast(long) cg.program.length);
        }
        else
        {
            cg.label(endLabel);
            cg.program[jzIdx].val = engine.makeInt(cast(long) cg.program.length);
        }
    }

    void generateVarDecl(VarDeclaration node)
    {
        bool isGlobal = isInGlobalScope();
        Node valueNode = node.value.get!Node;
        generateNode(valueNode);

        if (isGlobal)
            cg.emit(Instruction(OpCode.STOREG, engine.makeStr(node.id)));
        else
            cg.storeLocal(node.id);

        addVar(node.id, isGlobal);
    }

    void generateVarAssignment(VarAssignmentDecl node)
    {
        VarInfo* varInfo = lookupVar(node.id);
        if (varInfo is null)
            deErro(format("Variable não existe: %s", node.id), node.loc);

        Node valueNode = node.value.get!Node;
        generateNode(valueNode);
        cg.storeLocal(node.id);
    }

    void generateFuncDecl(FunctionDeclaration node)
    {
        string skipLabel = genLabel("skip_func");
        cg.emit(Instruction(OpCode.JMP, engine.makeInt(-1)));
        int skipIdx = cast(int) cg.program.length - 1;

        cg.label(node.name);

        // FunctionContext ctx;
        // ctx.name = node.name;
        // FunctionArg[] args;
        // foreach (arg; node.args)
        // {
        //     ctx.params ~= arg.name;
        //     args ~= FunctionArg(arg.name, arg.defaultValue, arg.isRef, arg.value);
        // }
        // functionArguments[node.name] = args;
        // funcContextStack ~= ctx;

        pushScope();

        // Os argumentos são passados via stack (em ordem reversa)
        // Armazena argumentos como variáveis locais
        foreach (arg; node.args)
        {
            cg.storeLocal(arg.name);
            addVar(arg.name, false);
        }

        bool temRetorno = false;

        foreach (stmt; node.body)
        {
            if (stmt.kind == NodeKind.Return)
                temRetorno = true;
            generateNode(stmt);
        }

        // verifica se a ultima instrução é um retorno pra ter isso como base pra retorno implicito
        // só pra garantir
        if (node.body[$ - 1].kind != NodeKind.Return)
            temRetorno = false;

        // Return implícito se não houver
        if (node.body.length == 0 || !temRetorno)
            cg.emit(Instruction(OpCode.RET));

        popScope();
        funcContextStack = funcContextStack[0 .. $ - 1];

        // Label de skip e patch
        cg.label(skipLabel);
        cg.program[skipIdx].val = engine.makeInt(cast(long) cg.program.length);
    }

    void generateCallExpr(CallExpr node)
    {
        if (node.id in externFuncs)
        {
            generateExternCall(node);
            return;
        }

        if (node.id == "__nucleo_harpy_escreva")
        {
            foreach (arg; node.args)
            {
                generateNode(arg);
                cg.emit(Instruction(OpCode.PRINT));
            }
            return;
        }

        if (node.id == "__nucleo_harpy_duplicar")
        {
            generateNode(node.args[0]);
            cg.emit(Instruction(OpCode.DUP));
            return;
        }

        if (node.id == "__nucleo_harpy_tamanho_vetor")
        {
            generateNode(node.args[0]);
            cg.emit(Instruction(OpCode.ARRL));
            return;
        }

        if (node.id == "__nucleo_harpy_tamanho_texto")
        {
            // node.args[0].value.get!string.length
            generateNode(node.args[0]);
            cg.emit(Instruction(OpCode.STRL));
            // cg.emit(Instruction(OpCode.PUSH, engine.makeInt()));
            return;
        }

        if (node.id == "__nucleo_harpy_tpd")
        {
            generateNode(node.args[0]);
            cg.emit(Instruction(OpCode.STOF));
            return;
        }

        if (node.id == "__nucleo_harpy_ipd")
        {
            generateNode(node.args[0]);
            cg.emit(Instruction(OpCode.ITOF));
            return;
        }

        if (node.id == "__nucleo_harpy_vetor_pop")
        {
            generateNode(node.args[0]);
            cg.emit(Instruction(OpCode.ARRPP));
            return;
        }

        // precisamos validar se há argumentos a serem tratados
        // se a nossa chamada soma(10) for feita, o numero de args da chamada é 1 enquanto se espera 2 pelo menos
        // logo ele cairá nesse if
        // node.print();
        // writeln(node.id, " ", functionArguments);
        FunctionArg[] fA = functionArguments[node.id];
        if (node.args.length < fA.length)
        {
            // precisamos preencher apenas os argumentos que FALTAM
            // se passamos 1 argumento mas a função espera 2, preenchemos do índice 1 em diante
            // loop REVERSO porque a pilha inverte a ordem!
            for (long i = cast(long) fA.length - 1; i >= cast(long) node.args.length;
                i--)
                generateNode(fA[i].value);
        }

        // primeiro geramos os argumentos opcionais em ordem reversa para seguir o padrão
        // pense na seguinte função:
        /*
        declarar saudar(nome texto = "Visitante", idade inteiro = 18) vazio {
            escreva("Olá, ", nome, "! Idade: ", idade, "\n")
        }

        se chamar assim: saudar()
        os argumentos serão completados na ordem: 18, Visitante
        seguindo a ideia de pilha (stack) da vm

        se chamar assim: saudar("Ana")
        os argumentos serão completados na ordem: 18, Ana

        e se chamar assim: saudar("Ana", 25)
        os argumentos serão completados na ordem: 25, Ana

        toda a ideia gira em torno da forma em que os argumentos são capturados pela vm
        o primeiro da lista será sempre o ultimo a sair
        */

        // vai gerar os argumentos
        // pense na seguinte função: declarar soma(x int, y int = 1) int;
        // ela tem um argumento padrão
        // se o node.args tiver apenas o x
        // ele será gerado tranquilamente

        // verifica nos argumentos da função se o argumento é por referencia ou não
        // só é valido para structs ou arrays
        foreach_reverse (ulong i, arg; node.args)
        {
            generateNode(arg);
            if (arg.type.type == Types.Array || arg.type.type == Types.Struct)
            {
                // emite cópia profunda se não for por referencia
                if (!fA[i].isRef)
                    cg.emit(Instruction(OpCode.DUP));
            }
        }

        cg.callLabel(node.id);
    }

    void generateExternCall(CallExpr node)
    {
        ExternFunc extFunc = externFuncs[node.id];
        FunctionArg[] fA = functionArguments[node.id];

        if (node.args.length < fA.length)
            for (long i = cast(long) fA.length - 1; i >= cast(long) node.args.length;
                i--)
                generateNode(fA[i].value);

        foreach_reverse (arg; node.args)
            generateNode(arg);

        cg.push(engine.makeInt(cast(long) node.args.length)); // argc
        cg.push(engine.makeStr(extFunc.library)); // nome da biblioteca
        cg.push(engine.makeStr(extFunc.name)); // nome da função
        cg.emit(Instruction(OpCode.FFIC)); // chama FFI
    }

    void generateBinaryExpr(BinaryExpr node)
    {
        // o true determina que independente da operação ele deve gerar um push a mais
        // acontece que a unica operação possivel com um vetor aqui e uma struct seria o '~='
        if (node.left.kind == NodeKind.MemberCallExpr && node.op == "~=")
            generateMemberCallExpr(cast(MemberCallExpr) node.left, true);
        else
            generateNode(node.left);
        generateNode(node.right);

        bool isFloat = node.left.type.baseType == BaseType.Float ||
            node.left.type.baseType == BaseType.Double ||
            node.left.type.baseType == BaseType.Real;
        bool isAny = node.left.type.baseType == BaseType.Any || node.right.type.baseType == BaseType
            .Any;
        bool isDiff = node.left.type.baseType != node.right.type.baseType;

        isAny = true;

        void erroBitWise(bool check, Loc loc)
        {
            if (check)
                deErro("Operadores bitwise não podem operar em números não inteiros.", loc);
        }

        if (node.op == "+" && node.left.type.baseType == BaseType.String)
        {
            cg.emit(Instruction(OpCode.PUSH, engine.makeStr(
                    node.left.value.get!string ~ node.right.value.get!string)));
            return;
        }

        OpCode opcode;

        switch (node.op)
        {
        case "+":
            if (isAny || isDiff)
                opcode = OpCode.ADD;
            else
                opcode = isFloat ? OpCode.ADDF : OpCode.ADDI;
            break;
        case "-":
            if (isAny || isDiff)
                opcode = OpCode.SUB;
            else
                opcode = isFloat ? OpCode.SUBF : OpCode.SUBI;
            break;
        case "*":
            if (isAny || isDiff)
                opcode = OpCode.MUL;
            else
                opcode = isFloat ? OpCode.MULF : OpCode.MULI;
            break;
        case "/":
            if (isAny || isDiff)
                opcode = OpCode.DIV;
            else
                opcode = isFloat ? OpCode.DIVF : OpCode.DIVI;
            break;
        case "%":
            if (isAny || isDiff)
                opcode = OpCode.MOD;
            else
                opcode = isFloat ? OpCode.MODF : OpCode.MODI;
            break;
        case "&":
            erroBitWise(isFloat, node.loc);
            opcode = OpCode.AND;
            break;
        case "|":
            erroBitWise(isFloat, node.loc);
            opcode = OpCode.OR;
            break;
        case "^":
            erroBitWise(isFloat, node.loc);
            opcode = OpCode.XOR;
            break;
        case "~":
            erroBitWise(isFloat, node.loc);
            opcode = OpCode.NOT;
            break;
        case "<<":
            erroBitWise(isFloat, node.loc);
            opcode = OpCode.SHL;
            break;
        case ">>":
            erroBitWise(isFloat, node.loc);
            opcode = OpCode.SHR;
            break;
        case ">>>":
            erroBitWise(isFloat, node.loc);
            opcode = OpCode.SAR;
            break;
        case "+=":
        case "~=":
        case "-=":
        case "/=":
        case "*=":
        case "%=":
        case "&=":
        case "|=":
        case "^=":
        case "<<=":
        case ">>=":
            final switch (node.op)
            {
            case "+=":
                cg.emit(Instruction(!isFloat ? OpCode.ADDI : OpCode.ADDF));
                break;
            case "-=":
                cg.emit(Instruction(!isFloat ? OpCode.SUBI : OpCode.SUBF));
                break;
            case "/=":
                cg.emit(Instruction(!isFloat ? OpCode.DIVI : OpCode.DIVF));
                break;
            case "*=":
                cg.emit(Instruction(!isFloat ? OpCode.MULI : OpCode.MULF));
                break;
            case "%=":
                cg.emit(Instruction(!isFloat ? OpCode.MODI : OpCode.MODF));
                break;
            case "&=":
                erroBitWise(isFloat, node.loc);
                cg.emit(Instruction(OpCode.AND));
                break;
            case "|=":
                erroBitWise(isFloat, node.loc);
                cg.emit(Instruction(OpCode.OR));
                break;
            case "^=":
                erroBitWise(isFloat, node.loc);
                cg.emit(Instruction(OpCode.XOR));
                break;
            case "<<=":
                erroBitWise(isFloat, node.loc);
                cg.emit(Instruction(OpCode.SHL));
                break;
            case ">>=":
                erroBitWise(isFloat, node.loc);
                cg.emit(Instruction(OpCode.SHR));
                break;
            case "~=":
                if (node.left.type.type == Types.Literal && node.left.type.baseType == BaseType
                    .String)
                    cg.emit(Instruction(OpCode.STRP));
                else
                    cg.emit(Instruction(OpCode.ARRP));
                break;
            }

            if (node.left.kind == NodeKind.MemberCallExpr)
            {
                MemberCallExpr mbr = cast(MemberCallExpr) node.left;
                cg.emit(Instruction(OpCode.STRUCTS, engine.makeInt(cast(long) mbr.fieldIdx))); // atualiza o valor
            }
            else if (node.left.kind == NodeKind.Identifier)
            {
                Identifier id = cast(Identifier) node.left;
                string name = id.value.get!string;
                VarInfo* varInfo = lookupVar(name);

                if (varInfo is null)
                    deErro(format("Váriavel não encontrada: %s", name), node.loc);

                if (varInfo.isGlobal)
                    cg.emit(Instruction(OpCode.STOREG, engine.makeStr(name)));
                else
                    cg.storeLocal(name);
            }
            else
                deErro(
                    "Para realizar esta operação é necessário que a expressão a esquerda seja uma variavel.",
                    node.left.loc
                );
            return;
        case "<":
            opcode = OpCode.LT;
            break;
        case "<=":
            opcode = OpCode.LTE;
            break;
        case ">":
            opcode = OpCode.GT;
            break;
        case ">=":
            opcode = OpCode.GTE;
            break;
        case "==":
            opcode = OpCode.EQ;
            break;
        case "!=":
            opcode = OpCode.NE;
            break;
        case "&&":
            opcode = OpCode.BBEQ;
            break;
        case "||":
            opcode = OpCode.BBNE;
            break;
        default:
            deErro(format("Operador não suportado: %s", node.op), node.loc);
            break;
        }

        cg.emit(Instruction(opcode));
    }

    void generateUnaryExpr(UnaryExpr node)
    {
        generateNode(node.operand);

        switch (node.op)
        {
        case "-":
            cg.push(engine.makeInt(-1));
            cg.emit(Instruction(OpCode.MUL));
            break;
        case "~":
            cg.emit(Instruction(OpCode.NOT));
            break;
        case "+":
            // só ignorar
            break;
        case "!":
            // TODO: NOT lógico
            cg.push(engine.makeBool(false));
            cg.emit(Instruction(OpCode.EQ));
            break;
        case "++":
        case "--":
            if (node.operand.kind == NodeKind.Identifier)
            {
                // carrega o valor 10 na stack (por exemplo)
                generateNode(node.operand);
                cg.push(engine.makeInt(node.op == "++" ? 1 : -1));
                // opera no ultimo valor adicionado na stack
                cg.emit(Instruction(OpCode.ADDI));
                // se não for postFix ele duplica o valor da stack
                if (!node.postFix) // duplica o valor com DUP
                    cg.emit(Instruction(OpCode.DUP));

                Identifier id = cast(Identifier) node.operand;
                VarInfo* varInfo = lookupVar(id.value.get!string);
                if (varInfo.isGlobal)
                    cg.emit(Instruction(OpCode.STOREG, engine.makeStr(id.value.get!string)));
                else
                    cg.storeLocal(id.value.get!string);
            }
            else if (node.operand.kind == NodeKind.MemberCallExpr)
            {
                MemberCallExpr mbr = cast(MemberCallExpr) node.operand;
                generateNode(mbr.object); // faz um push da struct para a stack
                generateNode(mbr.object); // faz um push da struct para a stack
                cg.emit(Instruction(OpCode.STRUCTG, engine.makeInt(cast(long) mbr.fieldIdx))); // obtem o valor do campo
                cg.push(engine.makeInt(node.op == "++" ? 1 : -1)); // push de 1
                cg.emit(Instruction(OpCode.ADDI)); // soma e coloca o resultado na pilha
                cg.emit(Instruction(OpCode.STRUCTS, engine.makeInt(cast(long) mbr.fieldIdx))); // atualiza o valor
            }
            else
                deErro("A expressao unaria '++' e '--' espera que o operando seja uma variavel.", node
                        .operand.loc);
            break;
        default:
            deErro(format("Operador não suportado: %s", node.op), node.loc);
            break;
        }
    }

    void generateIdentifier(Identifier node)
    {
        string name = node.value.get!string;
        VarInfo* varInfo = lookupVar(name);

        if (varInfo is null)
            deErro(format("Váriavel não encontrada: %s", name), node.loc);

        if (varInfo.isGlobal)
            cg.emit(Instruction(OpCode.LOADG, engine.makeStr(name)));
        else
            cg.loadLocal(name);
    }

    pragma(inline, true);
    void generateLiteral(Node node)
    {
        cg.push(makeValue(node));
    }

    void functionInitializer(FunctionDeclaration node)
    {
        FunctionContext ctx;
        ctx.name = node.name;
        FunctionArg[] args;
        foreach (arg; node.args)
        {
            ctx.params ~= arg.name;
            args ~= FunctionArg(arg.name, arg.defaultValue, arg.isRef, arg.value);
        }
        functionArguments[node.name] = args;
        funcContextStack ~= ctx;
    }
}
