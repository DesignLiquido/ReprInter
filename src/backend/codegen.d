module backend.codegen;

import std.stdio, std.format, std.conv, std.algorithm, std.string;
import core.sys.posix.dlfcn;
import frontend.parser.ast, frontend.type;
import backend.harpyvm, erro;

class CodeGen
{
private:
    DiagnosticError error;
    HarpyVM engine;
    HarpyCG cg;
    string[] externLibs;
    bool halt = false;

    struct FunctionContext
    {
        string name;
        string[] params;
        int localVarCount;
    }

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

        default:
            error.addError(Diagnostic(format("Literal desconhecido: %s", node.kind), node
                    .loc));
            throw new Exception(format("Literal desconhecido: %s", node.kind));
        }
    }

public:
    void*[string] libs;
    ffi_extern_function[string] externalFunctions;

    this(HarpyVM engine, DiagnosticError error, ref string[] externLibs)
    {
        this.engine = engine;
        this.externLibs = externLibs;
        this.cg = new HarpyCG(engine);
        this.error = error;
        pushScope();
    }

    Instruction[] generate(Program program)
    {
        cg.label("main");

        foreach (stmt; program.body)
            generateNode(stmt);

        if (!halt)
            cg.emit(Instruction(OpCode.HALT, engine.makeInt(0)));
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

        case NodeKind.IntLiteral:
        case NodeKind.DoubleLiteral:
        case NodeKind.StringLiteral:
            generateLiteral(node);
            break;

        case NodeKind.EoP:
            halt = true;
            cg.emit(Instruction(OpCode.HALT));
            break;

        default:
            error.addError(Diagnostic(format("Code generation not implemented for: %s", node.kind), node
                    .loc));
            throw new Exception(format("Code generation not implemented for: %s", node.kind));
        }
    }

    void generateReturn(Return node)
    {
        if (node.ret && node.value.convertsTo!Node)
        {
            Node returnValue = node.value.get!Node;
            generateNode(returnValue);
        }
        cg.emit(Instruction(OpCode.RET, engine.makeInt(0)));
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

    void generateFuncDecl(FunctionDeclaration node)
    {
        string skipLabel = genLabel("skip_func");
        cg.emit(Instruction(OpCode.JMP, engine.makeInt(-1)));
        int skipIdx = cast(int) cg.program.length - 1;

        cg.label(node.name);

        FunctionContext ctx;
        ctx.name = node.name;
        foreach (arg; node.args)
            ctx.params ~= arg.name;
        funcContextStack ~= ctx;

        pushScope();

        // Os argumentos são passados via stack (em ordem reversa)
        // Armazena argumentos como variáveis locais
        foreach (arg; node.args)
        {
            cg.storeLocal(arg.name);
            addVar(arg.name, false);
        }

        foreach (stmt; node.body)
            generateNode(stmt);

        // Return implícito se não houver
        if (node.body.length == 0)
            cg.emit(Instruction(OpCode.RET, engine.makeInt(0)));

        popScope();
        funcContextStack = funcContextStack[0 .. $ - 1];

        // Label de skip e patch
        cg.label(skipLabel);
        cg.program[skipIdx].val = engine.makeInt(cast(long) cg.program.length);
    }

    void generateCallExpr(CallExpr node)
    {
        if (node.id == "__corevm_print")
        {
            foreach_reverse (arg; node.args)
            {
                generateNode(arg);
                cg.emit(Instruction(OpCode.PRINT));
            }
            return;
        }

        foreach_reverse (arg; node.args)
            generateNode(arg);

        cg.callLabel(node.id);
    }

    void generateBinaryExpr(BinaryExpr node)
    {
        generateNode(node.left);
        generateNode(node.right);

        bool isFloat = node.left.type.baseType == BaseType.Float ||
            node.left.type.baseType == BaseType.Double ||
            node.left.type.baseType == BaseType.Real;

        if (node.left.type.baseType == BaseType.String)
        {
            cg.emit(Instruction(OpCode.PUSH, engine.makeStr(
                    node.left.value.get!string ~ node.right.value.get!string)));
            return;
        }

        OpCode opcode;

        switch (node.op)
        {
        case "+":
            opcode = isFloat ? OpCode.ADDF : OpCode.ADDI;
            break;
        case "-":
            opcode = isFloat ? OpCode.SUBF : OpCode.SUBI;
            break;
        case "*":
            opcode = isFloat ? OpCode.MULF : OpCode.MULI;
            break;
        case "/":
            opcode = isFloat ? OpCode.DIVF : OpCode.DIVI;
            break;
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
        default:
            error.addError(Diagnostic(format("Unsupported binary operator: %s", node.op), node.loc));
            throw new Exception(format("Unsupported binary operator: %s", node.op));
        }

        cg.emit(Instruction(opcode, engine.makeInt(0)));
    }

    void generateUnaryExpr(UnaryExpr node)
    {
        generateNode(node.operand);

        switch (node.op)
        {
        case "-":
            cg.push(engine.makeInt(-1));
            bool isFloat = node.operand.type.baseType == BaseType.Float ||
                node.operand.type.baseType == BaseType.Double;
            cg.emit(Instruction(isFloat ? OpCode.MULF : OpCode.MULI, engine.makeInt(0)));
            break;

        case "!":
            // TODO: NOT lógico
            cg.push(engine.makeBool(false));
            cg.emit(Instruction(OpCode.EQ, engine.makeInt(0)));
            break;

        case "++":
        case "--":
            if (!node.postFix)
            {
                generateNode(node.operand);
                cg.push(engine.makeInt(node.op == "++" ? 1 : -1));
                cg.emit(Instruction(OpCode.ADDI, engine.makeInt(0)));

                if (node.operand.kind == NodeKind.Identifier)
                {
                    Identifier id = cast(Identifier) node.operand;
                    VarInfo* varInfo = lookupVar(id.value.get!string);
                    if (varInfo.isGlobal)
                        cg.emit(Instruction(OpCode.STOREG, engine.makeStr(id.value.get!string)));
                    else
                        cg.storeLocal(id.value.get!string);
                }
            }
            else
            {
                // TODO:
                // Post-incremento: retorna valor antigo, depois modifica
                // (mais complexo, requer duplicação do valor)
            }
            break;

        default:
            error.addError(Diagnostic(format("Unsupported unary operator: %s", node.op), node.loc));
            throw new Exception(format("Unsupported unary operator: %s", node.op));
        }
    }

    void generateIdentifier(Identifier node)
    {
        string name = node.value.get!string;
        VarInfo* varInfo = lookupVar(name);

        if (varInfo is null)
        {
            error.addError(Diagnostic(format("Variable not found: %s", name), node.loc));
            throw new Exception(format("Variable not found: %s", name));
        }

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
}
