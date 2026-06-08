module ast;

import std.stdio, std.format;
import token;
import std.conv;
import htype;

enum NodeKind : ubyte
{
    Program,
    
    StructDecl,
    FuncDecl,
    
    InstructionStmt,
    LabelStmt,
    
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

class StructField {
    string name;
    HType type;
    Position pos;

    ulong offset;
    uint padding;

    this(string name, HType type, Position pos)
    {
        this.name = name;
        this.type = type;
        this.pos = pos;
    }

    void setOffset(ulong off)
    {
        this.offset = off;
    }

    void setPadding(uint padd)
    {
        this.padding = padd;
    }
}

class StructDecl : Node {
    string name;
    StructField[] fields;

    this(string name, StructField[] fields, Position pos)
    {
        super(NodeKind.StructDecl, pos);
        this.name = name;
        this.fields = fields;
    }
}

class LabelStmt : Node
{
    string name;
    Node[] body;

    this(string name, Node[] body, Position pos)
    {
        super(NodeKind.LabelStmt, pos);
        this.name = name;
        this.body = body;
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
    Setar,
    Obter,
    Salte,
    Saltez,
    Saltenz,
    Compare,
    Aritmetica,
    Ref,
    Deref,
    Escreva,
    Alocan,
}

class InstructionStmt : Node
{
    Instruction kind;
    // para caso de casts
    HType to;
    // algumas instruções precisam de varios campos
    Node a, b, c;
    string d, e;
    ulong f;
    TokenKind op;

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

// converter DE, PARA, $a, $b
InstructionStmt instrConverter(HType de, HType para, Token a, Token b, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Conv, de, pos);
    instr.a = new IDentifier(a.value.s, a.pos);
    instr.b = new IDentifier(b.value.s, b.pos);
    instr.to = para;
    return instr;
}

// setar T $ptr, field, $val
InstructionStmt instrSetar(HType type, Token ptr, Token field, Token val, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Setar, type, pos);
    instr.a = new IDentifier(ptr.value.s, ptr.pos);
    instr.b = new IDentifier(field.value.s, field.pos);
    instr.c = new IDentifier(val.value.s, val.pos);
    return instr;
}

// obter T $ptr, field, $val
InstructionStmt instrObter(HType type, Token ptr, Token field, Token val, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Obter, type, pos);
    instr.a = new IDentifier(ptr.value.s, ptr.pos);
    instr.b = new IDentifier(field.value.s, field.pos);
    instr.c = new IDentifier(val.value.s, val.pos);
    return instr;
}

// salte .label
InstructionStmt instrSalte(string label, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Salte, HType.init, pos);
    instr.d = label;
    return instr;
}

// salte(z|nz) $cond, .label1, .label2
InstructionStmt instrSalteCond(Token cond, string label1, string label2, bool nz, Position pos)
{
    InstructionStmt instr = new InstructionStmt(nz ? Instruction.Saltenz : Instruction.Saltez, HType.init, pos);
    instr.a = new IDentifier(cond.value.s, cond.pos);
    instr.d = label1;
    instr.e = label2;
    return instr;
}

// compare T $x OP $y, $z
InstructionStmt instrCompare(HType type, Token x, TokenKind op, Token y, Token z, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Compare, type, pos);
    instr.a = new IDentifier(x.value.s, x.pos);
    instr.b = new IDentifier(y.value.s, y.pos);
    instr.c = new IDentifier(z.value.s, z.pos);
    instr.op = op;
    return instr;
}

// (soma|sub|...) T, $a, $b, $c
InstructionStmt instrBiOp(TokenKind op, HType t, Token a, Token b, Token c, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Aritmetica, t, pos);
    instr.a = new IDentifier(a.value.s, a.pos);
    instr.b = new IDentifier(b.value.s, b.pos);
    instr.c = new IDentifier(c.value.s, c.pos);
    instr.op = op;
    return instr;
}

// (ref|deref|escreva) $a, $b
InstructionStmt instrMem(Instruction kind, Token a, Token b, Position pos)
{
    InstructionStmt instr = new InstructionStmt(kind, HType.init, pos);
    instr.a = new IDentifier(a.value.s, a.pos);
    instr.b = new IDentifier(b.value.s, b.pos);
    return instr;
}

// alocarn T, $target, size
InstructionStmt instrAlocan(HType type, Token a, ulong size, Position pos)
{
    InstructionStmt instr = new InstructionStmt(Instruction.Alocan, type, pos);
    instr.a = new IDentifier(a.value.s, a.pos);
    instr.f = size;
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
                
            case Instruction.Aritmetica:
            case Instruction.Setar:
            case Instruction.Obter:
                writef("%s %s, ", instr.kind == Instruction.Aritmetica ? instr.op : instr.kind, instr.type.toStr());
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

            case Instruction.Salte:
                writefln("Salte %s", instr.d);
                return;

            case Instruction.Saltez:
            case Instruction.Saltenz:
                writef("Salte%s ", instr.kind == Instruction.Saltenz ? "nz" : "z");
                debugNode(instr.a);
                writefln(", %s, %s", instr.d, instr.e);
                return;

            case Instruction.Compare:
                writef("Compare %s, ", instr.type.toStr());
                debugNode(instr.a);
                writef(" %s ", instr.op);
                debugNode(instr.b);
                write(", ");
                debugNode(instr.c);
                writeln();
                return;

            case Instruction.Ref:
            case Instruction.Deref:
            case Instruction.Escreva:
                writef("%s, ", instr.kind);
                debugNode(instr.a);
                write(", ");
                debugNode(instr.b);
                writeln();
                return;

            case Instruction.Alocan:
                write("Alocan, ");
                debugNode(instr.a);
                writefln(", %d", instr.f);
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

    case NodeKind.StructDecl:
        StructDecl decl = cast(StructDecl) node;
        writefln("StructDecl(%s):", decl.name);
        for (ulong i; i < decl.fields.length; i++)
        {
            printIndent(indent+2);
            StructField field = decl.fields[i];
            writefln("%s: %s -> offset(%d) -> padding(%d)", field.name, field.type.toStr(), 
                field.offset, field.padding);
        }
        return;

    case NodeKind.LabelStmt:
        LabelStmt label = cast(LabelStmt) node;
        writefln("LabelStmt(%s):", label.name);
        for (ulong i; i < label.body.length; i++)
            debugNode(label.body[i], indent + 4);
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
