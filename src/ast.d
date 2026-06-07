module ast;

import std.stdio, std.format;
import token;
import std.conv;
import htype;

enum NodeKind : ubyte
{
    Program,
    FuncDecl,
    InstructionStmt,
    CallExpr,
    Identifier, // x
    IDentifier, // $x
    IntLit,
    DoubleLit,
    StringLit,
}

abstract class Node
{
    NodeKind kind;
    Position pos;
    HType type;

    this(NodeKind k, Position p)
    {
        kind = k;
        pos = p;
    }
}

class Program : Node
{
    Node[] decls;
    this(Node[] decls)
    {
        super(NodeKind.Program, Position.init);
        this.decls = decls;
    }
}

class FuncArg
{
    string name;
    HType type;

    this(string name, HType type)
    {
        this.name = name;
        this.type = type;
    }
}

class FuncDecl : Node
{
    string name;
    FuncArg[] args;
    Node[] body;
    bool isExtern, isVariadic;

    this(string name, HType type, FuncArg[] args, Node[] body, bool isExtern, bool isVariadic, Position pos)
    {
        super(NodeKind.FuncDecl, pos);
        this.name = name;
        this.type = type;
        this.args = args;
        this.isExtern = isExtern;
        this.isVariadic = isVariadic;
        this.body = body;
    }
}

class Identifier : Node
{
    string val;
    this(dstring val, Position pos)
    {
        super(NodeKind.Identifier, pos);
        this.val = to!string(val);
    }
}

class IDentifier : Node
{
    string val;
    this(dstring val, Position pos)
    {
        super(NodeKind.IDentifier, pos);
        this.val = to!string(val);
    }
}

class IntLit : Node
{
    long val;
    this(long val, Position pos)
    {
        super(NodeKind.IntLit, pos);
        this.val = val;
    }
}

class DoubleLit : Node
{
    double val;
    this(double val, Position pos)
    {
        super(NodeKind.DoubleLit, pos);
        this.type = new HTypeBuiltin(HTBase.F64);
        this.val = val;
    }
}

class StringLit : Node
{
    string val;
    this(string val, Position pos)
    {
        super(NodeKind.StringLit, pos);
        this.type = new HTypeBuiltin(HTBase.I64);
        this.val = val;
    }
}

class CallExpr : Node
{
    string name;
    string[] args;
    
    this(string name, string[] args, Position pos)
    {
        super(NodeKind.CallExpr, pos);
        this.name = name;
        this.args = args;
    }
}

// classe generica pra toda e qualquer instrução
// alloca i32 $x

enum Instruction : ubyte
{
    Aloca,
    Ime,
    Ret,
    Chamada,
    Conv,
    Soma,
}

class InstructionStmt : Node
{
    Instruction kind;
    // para caso de casts
    HType to;
    // algumas instruções precisam de varios campos
    Node a, b, c;

    this(Instruction kind, HType type, Position pos)
    {
        super(NodeKind.InstructionStmt, pos);
        this.kind = kind;
        this.type = type;
    }
}

// instruções

// aloca T, $ID
InstructionStmt instrAloca(HType t, Token id, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Aloca, t, pos);
    instr.a = new IDentifier(id.value.s, id.pos);
    return instr;
}

// ret $ID
InstructionStmt instrRet(Token id, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Ret, HType.init, pos);
    instr.a = new IDentifier(id.value.s, id.pos);
    return instr;
}

// imediato T, $ID, EXPR
InstructionStmt instrIme(HType t, Token id, Node val, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Ime, t, pos);
    instr.a = new IDentifier(id.value.s, id.pos);
    instr.b = val;
    return instr;
}

// call T, CALLEXPR, $res
InstructionStmt instrChamada(HType t, Node call, Token res, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Chamada, t, pos);
    instr.a = call;
    instr.b = new IDentifier(res.value.s, res.pos);
    return instr;
}

// soma T, $a, $b, $c
InstructionStmt instrSoma(HType t, Token a, Token b, Token c, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Soma, t, pos);
    instr.a = new IDentifier(a.value.s, a.pos);
    instr.b = new IDentifier(b.value.s, b.pos);
    instr.c = new IDentifier(c.value.s, c.pos);
    return instr;
}

// converter DE, PARA, $a, $b
InstructionStmt instrConverter(HType de, HType para, Token a, Token b, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Conv, de, pos);
    instr.a = new IDentifier(a.value.s, a.pos);
    instr.b = new IDentifier(b.value.s, b.pos);
    instr.to = para;
    return instr;
}

void printIndent(int indent = 0)
{
    for (int i; i < indent; i++)
        write(" ");
}

void debugNode(Node node, int indent = 0)
{
    import std.array : replicate;

    if (node is null)
        return;

    printIndent(indent);

    final switch (node.kind)
    {
    case NodeKind.Program:
        writeln("Program:");
        Program p = cast(Program) node;
        for (ulong i; i < p.decls.length; i++)
            debugNode(p.decls[i], indent + 4);
        return;

    case NodeKind.FuncDecl:
        FuncDecl fn = cast(FuncDecl) node;
        writefln("FuncDecl(%s): %s", fn.name, fn.type.toStr());
        printIndent(indent);
        writefln("Arguments: [");
        for (ulong i; i < fn.args.length; i++)
        {
            printIndent(indent + 2);
            writefln("%s: %s", fn.args[i].name, fn.args[i].type.toStr());
        }
        printIndent(indent);
        writefln("]");
        printIndent(indent);
        writefln("Body:");
        for (ulong i; i < fn.body.length; i++)
            debugNode(fn.body[i], indent + 4);
        return;

    case NodeKind.InstructionStmt:
        InstructionStmt instr = cast(InstructionStmt) node;
        final switch (instr.kind)
        {
            case Instruction.Aloca:
                writef("Aloca %s, ", instr.type.toStr());
                debugNode(instr.a);
                writeln();
                return;

            case Instruction.Soma:
                writef("Soma %s, ", instr.type.toStr());
                debugNode(instr.a);
                write(", ");
                debugNode(instr.b);
                write(", ");
                debugNode(instr.c);
                writeln();
                return;

            case Instruction.Chamada:
                writef("Chamada %s, ", instr.type.toStr());
                debugNode(instr.a);
                write(", ");
                debugNode(instr.b);
                write(", ");
                debugNode(instr.c);
                writeln();
                return;
            
            case Instruction.Ret:
                writef("Retorne ");
                debugNode(instr.a);
                writeln();
                return;

            case Instruction.Ime:
                writef("Imediato %s, ", instr.type.toStr());
                debugNode(instr.a);
                write(", ");
                debugNode(instr.b);
                writeln();
                return;

            case Instruction.Conv:
                writef("Converter %s, %s, ", instr.type.toStr(), instr.to.toStr());
                debugNode(instr.a);
                write(", ");
                debugNode(instr.b);
                writeln();
                return;
        }
        return;

    case NodeKind.CallExpr:
        CallExpr call = cast(CallExpr) node;
        writef("%s(", call.name);
        for (ulong i; i < call.args.length; i++)
        {
            write(call.args[i]);
            if ((i + 1) < call.args.length)
                write(", ");
        }
        writeln(")");
        return;

    case NodeKind.Identifier:
        return writef("%s", (cast(Identifier) node).val);

    case NodeKind.IDentifier:
        return writef("$%s", (cast(IDentifier) node).val);

    case NodeKind.IntLit:
        return writef("IntLit(%d)", (cast(IntLit) node).val);

    case NodeKind.DoubleLit:
        return writef("DoubleLit(%f)", (cast(DoubleLit) node).val);

    case NodeKind.StringLit:
        return writef("StringLit(%s)", (cast(StringLit) node).val);
    }
}
