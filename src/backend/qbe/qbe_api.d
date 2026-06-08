module backend.qbe.qbe_api;

import std.array : Appender, appender;
import std.format : format, formattedWrite;
import std.string : toStringz, fromStringz;
import std.conv : to;
import std.exception : enforce;
import std.stdio : stderr, writeln;

// ---------------------------------------------------------------------------
// Alias de conveniência
// ---------------------------------------------------------------------------

alias StrBuf = Appender!string;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum QBEType
{
    Byte, // 1
    Halfword, // 2
    Word, // 4
    Single, // 4
    Double, // 8
    Long, // 8
}

enum Linkage
{
    Private,
    Public,
    Section,
    Thread
}

enum QBECmp
{
    // Inteiros (signed)
    Eq,
    Ne,
    Slt,
    Sle,
    Sgt,
    Sge,
    // Inteiros (unsigned)
    Ult,
    Ule,
    Ugt,
    Uge,
    // Floats
    Lt,
    Le,
    Gt,
    Ge,
    O,
    Uo,
}

string cmpPrefix(QBECmp c) pure nothrow
{
    final switch (c)
    {
    case QBECmp.Eq:
        return "eq";
    case QBECmp.Ne:
        return "ne";
    case QBECmp.Slt:
        return "slt";
    case QBECmp.Sle:
        return "sle";
    case QBECmp.Sgt:
        return "sgt";
    case QBECmp.Sge:
        return "sge";
    case QBECmp.Ult:
        return "ult";
    case QBECmp.Ule:
        return "ule";
    case QBECmp.Ugt:
        return "ugt";
    case QBECmp.Uge:
        return "uge";
    case QBECmp.Lt:
        return "lt";
    case QBECmp.Le:
        return "le";
    case QBECmp.Gt:
        return "gt";
    case QBECmp.Ge:
        return "ge";
    case QBECmp.O:
        return "o";
    case QBECmp.Uo:
        return "uo";
    }
}

string typePrefix(QBEType t) pure nothrow
{
    final switch (t)
    {
    case QBEType.Word:
        return "w";
    case QBEType.Long:
        return "l";
    case QBEType.Single:
        return "s";
    case QBEType.Double:
        return "d";
    case QBEType.Byte:
        return "b";
    case QBEType.Halfword:
        return "h";
    }
}

string typePrefixN(QBEType t) pure nothrow
{
    final switch (t)
    {
    case QBEType.Word:
        return "4";
    case QBEType.Long:
        return "8";
    case QBEType.Single:
        return "4";
    case QBEType.Double:
        return "8";
    case QBEType.Byte:
        return "4";
    case QBEType.Halfword:
        return "4";
    }
}

string getCastOp(QBEType from, QBEType to, bool signed_ = true) pure nothrow
{
    // byte => word/long
    if (from == QBEType.Byte && (to == QBEType.Word || to == QBEType.Long))
        return signed_ ? "extsb" : "extub";

    // halfword => word/long
    if (from == QBEType.Halfword && (to == QBEType.Word || to == QBEType.Long))
        return signed_ ? "extsh" : "extuh";

    // inteiro => inteiro
    if (from == QBEType.Word && to == QBEType.Long)
        return signed_ ? "extsw" : "extuw";
    if (from == QBEType.Long && to == QBEType.Word)
        return "copy";

    // inteiro => float
    if (from == QBEType.Word && to == QBEType.Single)
        return signed_ ? "swtof" : "uwtof";
    if (from == QBEType.Word && to == QBEType.Double)
        return signed_ ? "swtod" : "uwtod";
    if (from == QBEType.Long && to == QBEType.Single)
        return signed_ ? "sltof" : "ultof";
    if (from == QBEType.Long && to == QBEType.Double)
        return signed_ ? "sltod" : "ultod";

    // float => inteiro
    if (from == QBEType.Single && to == QBEType.Word)
        return signed_ ? "stosi" : "stoui";
    if (from == QBEType.Single && to == QBEType.Long)
        return signed_ ? "stosl" : "stoul";
    if (from == QBEType.Double && to == QBEType.Word)
        return signed_ ? "dtosi" : "dtoui";
    if (from == QBEType.Double && to == QBEType.Long)
        return signed_ ? "dtosl" : "dtoul";

    // float => float
    if (from == QBEType.Single && to == QBEType.Double)
        return "exts";
    if (from == QBEType.Double && to == QBEType.Single)
        return "truncd";

    return "copy";
}

// ---------------------------------------------------------------------------
// QBEValue
// ---------------------------------------------------------------------------

enum QBEValueKind
{
    Temp,
    Global,
    Const,
    FloatConst,
    SingleConst
}

struct QBEValue
{
    QBEValueKind kind;
    QBEType type;

    union
    {
        long ival;
        double dval;
        float fval;
    }

    string name; // %foo, $foo, 42, d_0x1p+0, ...

    static QBEValue makeTemp(string name, QBEType t = QBEType.Long)
    {
        QBEValue v;
        v.kind = QBEValueKind.Temp;
        v.type = t;
        v.name = "%" ~ name;
        return v;
    }

    static QBEValue makeGlobal(string name, QBEType t = QBEType.Long)
    {
        QBEValue v;
        v.kind = QBEValueKind.Global;
        v.type = t;
        v.name = "$" ~ name;
        return v;
    }

    static QBEValue makeConst(long value, QBEType t = QBEType.Long)
    {
        QBEValue v;
        v.kind = QBEValueKind.Const;
        v.type = t;
        v.ival = value;
        v.name = value.to!string;
        return v;
    }

    static QBEValue makeFloatConst(double value)
    {
        import std.format : format;

        QBEValue v;
        v.kind = QBEValueKind.FloatConst;
        v.type = QBEType.Double;
        v.dval = value;
        v.name = format!"d_%a"(value);
        return v;
    }

    static QBEValue makeSingleConst(float value)
    {
        import std.format : format;

        QBEValue v;
        v.kind = QBEValueKind.SingleConst;
        v.type = QBEType.Single;
        v.fval = value;
        v.name = format!"s_%a"(value);
        return v;
    }

    string str() const pure
    {
        return name;
    }

    void emitTyped(ref StrBuf buf) const
    {
        buf.formattedWrite!"%s %s"(typePrefix(type), name);
    }
}

// ---------------------------------------------------------------------------
// QBEInstr
// ---------------------------------------------------------------------------

enum QBEInstrKind
{
    Assign,
    Volatile,
    Jump,
    Jnz,
    Return,
    Call,
    CallVoid,
    Alloc,
    Store,
    Load,
    Compare,
    Cast,
    Phi,
}

struct PhiEntry
{
    QBEValue val;
    string label;
}

struct QBEInstr
{
    QBEInstrKind kind;
    QBEValue result;
    QBEType type;
    string op;

    bool hasValue;
    QBEValue retVal;

    QBEValue[] args;

    PhiEntry[] phiEntries;

    QBEType fromType;
    bool signed;

    void emit(ref StrBuf buf) const
    {
        final switch (kind)
        {
        case QBEInstrKind.Assign:
            buf.formattedWrite!"    %s =%s %s "(result.str, typePrefix(type), op);
            foreach (i, ref a; args)
            {
                if (i > 0)
                    buf.put(", ");
                buf.put(a.str);
            }
            buf.put("\n");
            break;

        case QBEInstrKind.Volatile:
            buf.formattedWrite!"    %s "(op);
            foreach (i, ref a; args)
            {
                if (i > 0)
                    buf.put(", ");
                buf.put(a.str);
            }
            buf.put("\n");
            break;

        case QBEInstrKind.Jump:
            buf.formattedWrite!"    jmp @%s\n"(op);
            break;

        case QBEInstrKind.Jnz:
            // op == "ifTrue\0ifFalse" — guardado como "ifTrue|ifFalse"
            import std.string : indexOf;

            auto sep = op.indexOf('|');
            auto trueL = op[0 .. sep];
            auto falseL = op[sep + 1 .. $];
            buf.formattedWrite!"    jnz %s, @%s, @%s\n"(args[0].str, trueL, falseL);
            break;

        case QBEInstrKind.Return:
            if (hasValue)
                buf.formattedWrite!"    ret %s\n"(retVal.str);
            else
                buf.put("    ret\n");
            break;

        case QBEInstrKind.Call:
            buf.formattedWrite!"    %s =%s call %s("(result.str, typePrefix(type), args[0].str);
            foreach (i; 1 .. args.length)
            {
                if (i > 1)
                    buf.put(", ");
                args[i].emitTyped(buf);
            }
            buf.put(")\n");
            break;

        case QBEInstrKind.CallVoid:
            buf.formattedWrite!"    call %s("(args[0].str);
            foreach (i; 1 .. args.length)
            {
                if (i > 1)
                    buf.put(", ");
                args[i].emitTyped(buf);
            }
            buf.put(")\n");
            break;

        case QBEInstrKind.Alloc:
            buf.formattedWrite!"    %s =l alloc%s %d\n"(result.str, op, args[0].ival);
            break;

        case QBEInstrKind.Store:
            buf.formattedWrite!"    store%s %s, %s\n"(typePrefix(type), args[0].str, args[1].str);
            break;

        case QBEInstrKind.Load:
            if (type == QBEType.Byte)
                buf.formattedWrite!"    %s =w loadsb %s\n"(result.str, args[0].str);
            else
                buf.formattedWrite!"    %s =%s load%s %s\n"(
                    result.str, typePrefix(type), typePrefix(type), args[0].str);
            break;

        case QBEInstrKind.Compare:
            buf.formattedWrite!"    %s =w c%s%s %s, %s\n"(
                result.str, op, typePrefix(type), args[0].str, args[1].str);
            break;

        case QBEInstrKind.Cast:
            buf.formattedWrite!"    %s =%s %s %s\n"(
                result.str, typePrefix(type),
                getCastOp(fromType, type, signed), args[0].str);
            break;

        case QBEInstrKind.Phi:
            buf.formattedWrite!"    %s =%s phi "(result.str, typePrefix(type));
            foreach (i, ref e; phiEntries)
            {
                if (i > 0)
                    buf.put(", ");
                buf.formattedWrite!"@%s %s"(e.label, e.val.str);
            }
            buf.put("\n");
            break;
        }
    }
}

// ---------------------------------------------------------------------------
// QBEBlock
// ---------------------------------------------------------------------------

class QBEBlock
{
    string name;
    QBEInstr[] instrs;

    this(string n)
    {
        name = n;
    }

    void add(QBEInstr instr)
    {
        instrs ~= instr;
    }

    void emit(ref StrBuf buf) const
    {
        buf.formattedWrite!"@%s\n"(name);
        foreach (ref i; instrs)
            i.emit(buf);
    }
}

// ---------------------------------------------------------------------------
// QBEParam
// ---------------------------------------------------------------------------

struct QBEParam
{
    QBEType type;
    string name;

    void emit(ref StrBuf buf) const
    {
        buf.formattedWrite!"%s %%%s"(typePrefix(type), name);
    }
}

// ---------------------------------------------------------------------------
// QBEFunction
// ---------------------------------------------------------------------------

class QBEFunction
{
    string name;
    QBEType returnType;
    QBEParam[] params;
    QBEBlock[] blocks;
    Linkage linkage;
    bool isVariadic;
    bool exported;

    this(string n, QBEType retType = QBEType.Long, Linkage lnk = Linkage.Private)
    {
        name = n;
        returnType = retType;
        linkage = lnk;
    }

    void addParam(QBEType t, string n)
    {
        params ~= QBEParam(t, n);
    }

    QBEBlock addBlock(string n)
    {
        auto b = new QBEBlock(n);
        blocks ~= b;
        return b;
    }

    void emit(ref StrBuf buf) const
    {
        if (exported || linkage == Linkage.Public)
            buf.put("export ");
        else if (linkage == Linkage.Section)
            buf.put("section ");
        else if (linkage == Linkage.Thread)
            buf.put("thread ");

        buf.formattedWrite!"function %s $%s("(typePrefix(returnType), name);

        foreach (i, ref p; params)
        {
            if (i > 0)
                buf.put(", ");
            p.emit(buf);
        }
        if (isVariadic)
            buf.put(", ...");
        buf.put(") {\n");

        foreach (b; blocks)
            b.emit(buf);

        buf.put("}\n");
    }
}

// ---------------------------------------------------------------------------
// QBEDataItem / QBEData
// ---------------------------------------------------------------------------

struct QBEDataItem
{
    QBEType type;
    QBEValue value;

    void emit(ref StrBuf buf) const
    {
        buf.formattedWrite!"%s %s"(typePrefix(type), value.str);
    }
}

class QBEData
{
    string name;
    Linkage linkage;
    QBEDataItem[] items;
    size_t _align;
    bool exported;

    this(string n, Linkage lnk = Linkage.Private, size_t align_ = 0)
    {
        name = n;
        linkage = lnk;
        _align = align_;
    }

    private void addItem(QBEDataItem item)
    {
        items ~= item;
    }

    void addByte(long v)
    {
        addItem(QBEDataItem(QBEType.Byte, QBEValue.makeConst(v, QBEType.Byte)));
    }

    void addHalf(long v)
    {
        addItem(QBEDataItem(QBEType.Halfword, QBEValue.makeConst(v, QBEType.Halfword)));
    }

    void addWord(long v)
    {
        addItem(QBEDataItem(QBEType.Word, QBEValue.makeConst(v, QBEType.Word)));
    }

    void addLong(long v)
    {
        addItem(QBEDataItem(QBEType.Long, QBEValue.makeConst(v, QBEType.Long)));
    }

    void addString(string s)
    {
        foreach (ch; s)
            addByte(cast(long) ch);
        addByte(0);
    }

    void emit(ref StrBuf buf) const
    {
        if (exported || linkage == Linkage.Public)
            buf.put("export ");
        else if (linkage == Linkage.Section)
            buf.put("section ");
        else if (linkage == Linkage.Thread)
            buf.put("thread ");

        buf.formattedWrite!"data $%s = "(name);

        if (_align > 0)
            buf.formattedWrite!"align %d "(cast(ulong) _align);

        buf.put("{ ");
        foreach (i, ref item; items)
        {
            if (i > 0)
                buf.put(", ");
            item.emit(buf);
        }
        buf.put(" }\n");
    }
}

// ---------------------------------------------------------------------------
// QBEAggregate
// ---------------------------------------------------------------------------

struct QBETypeField
{
    QBEType type;
    size_t count;

    void emit(ref StrBuf buf) const
    {
        if (count > 1)
            buf.formattedWrite!"%s %d"(typePrefix(type), cast(ulong) count);
        else
            buf.put(typePrefix(type));
    }
}

class QBEAggregate
{
    string name;
    QBETypeField[] fields;
    size_t _align;
    bool opaque;

    this(string n, size_t align_ = 0, bool opaque_ = false)
    {
        name = n;
        _align = align_;
        opaque = opaque_;
    }

    void addField(QBEType t, size_t count = 1)
    {
        fields ~= QBETypeField(t, count);
    }

    void emit(ref StrBuf buf) const
    {
        buf.formattedWrite!"type :%s = "(name);

        if (opaque)
        {
            buf.put("{ 0 }\n");
            return;
        }

        if (_align > 0)
            buf.formattedWrite!"align %d "(cast(ulong) _align);

        buf.put("{ ");
        foreach (i, ref f; fields)
        {
            if (i > 0)
                buf.put(", ");
            f.emit(buf);
        }
        buf.put(" }\n");
    }
}

// ---------------------------------------------------------------------------
// QBEModule
// ---------------------------------------------------------------------------

class QBEModule
{
    QBEAggregate[] types;
    QBEData[] dataSegments;
    QBEFunction[] functions;

    void addType(QBEAggregate t)
    {
        types ~= t;
    }

    QBEData addData(string name, Linkage lnk = Linkage.Private, size_t align_ = 0)
    {
        auto d = new QBEData(name, lnk, align_);
        dataSegments ~= d;
        return d;
    }

    QBEFunction addFunction(string name,
        QBEType retType = QBEType.Long,
        Linkage lnk = Linkage.Private)
    {
        auto f = new QBEFunction(name, retType, lnk);
        functions ~= f;
        return f;
    }

    void emit(ref StrBuf buf) const
    {
        buf.put("# Generated by HARPY Compiler\n\n");

        if (types.length)
        {
            buf.put("# Types\n");
            foreach (t; types)
                t.emit(buf);
            buf.put("\n");
        }
        if (dataSegments.length)
        {
            buf.put("# Data\n");
            foreach (d; dataSegments)
                d.emit(buf);
            buf.put("\n");
        }
        if (functions.length)
        {
            buf.put("# Functions\n");
            foreach (f; functions)
            {
                f.emit(buf);
                buf.put("\n");
            }
        }
    }

    override string toString() const
    {
        auto buf = appender!string();
        emit(buf);
        return buf[];
    }

    void writeToFile(string filename) const
    {
        import std.file : write;

        write(filename, toString());
    }
}

// ---------------------------------------------------------------------------
// QBEBuilder
// ---------------------------------------------------------------------------

class QBEBuilder
{
    QBEModule module_;
    QBEFunction currentFunc;
    QBEBlock currentBlock;
    int tempCounter;
    int blockCounter;

    this()
    {
        module_ = new QBEModule();
    }

    private QBEValue tempVal(QBEType t = QBEType.Long)
    {
        return QBEValue.makeTemp(format!"t%d"(tempCounter++), t);
    }

    private void addInstr(QBEInstr instr)
    {
        currentBlock.add(instr);
    }

    QBEFunction startFunction(string name,
        QBEType retType = QBEType.Long,
        Linkage lnk = Linkage.Public)
    {
        currentFunc = module_.addFunction(name, retType, lnk);
        tempCounter = 0;
        blockCounter = 0;
        return currentFunc;
    }

    QBEBlock startBlock(string name = null)
    {
        auto n = (name !is null) ? name : format!"L%d"(blockCounter++);
        return currentBlock = currentFunc.addBlock(n);
    }

    QBEValue binop(string op, QBEType t, QBEValue a, QBEValue b)
    {
        QBEValue r = tempVal(t);
        QBEInstr instr;
        instr.kind = QBEInstrKind.Assign;
        instr.result = r;
        instr.type = t;
        instr.op = op;
        instr.args = [a, b];
        addInstr(instr);
        return r;
    }

    QBEValue add(QBEType t, QBEValue a, QBEValue b)
    {
        return binop("add", t, a, b);
    }

    QBEValue sub(QBEType t, QBEValue a, QBEValue b)
    {
        return binop("sub", t, a, b);
    }

    QBEValue mul(QBEType t, QBEValue a, QBEValue b)
    {
        return binop("mul", t, a, b);
    }

    QBEValue div(QBEType t, QBEValue a, QBEValue b)
    {
        return binop("div", t, a, b);
    }

    QBEValue rem(QBEType t, QBEValue a, QBEValue b)
    {
        return binop("rem", t, a, b);
    }

    QBEValue and(QBEType t, QBEValue a, QBEValue b)
    {
        return binop("and", t, a, b);
    }

    QBEValue or(QBEType t, QBEValue a, QBEValue b)
    {
        return binop("or", t, a, b);
    }

    QBEValue xor(QBEType t, QBEValue a, QBEValue b)
    {
        return binop("xor", t, a, b);
    }

    QBEValue cmp(string op, QBEType t, QBEValue a, QBEValue b)
    {
        QBEValue r = tempVal(QBEType.Word);
        QBEInstr instr;
        instr.kind = QBEInstrKind.Compare;
        instr.result = r;
        instr.type = t;
        instr.op = op;
        instr.args = [a, b];
        addInstr(instr);
        return r;
    }

    QBEValue alloc(long size, QBEType align_ = QBEType.Long)
    {
        QBEValue r = tempVal(QBEType.Long);
        QBEInstr instr;
        instr.kind = QBEInstrKind.Alloc;
        instr.result = r;
        instr.op = typePrefixN(align_);
        auto sizeVal = QBEValue.makeConst(size);
        sizeVal.ival = size;
        instr.args = [sizeVal];
        addInstr(instr);
        return r;
    }

    void store(QBEType t, QBEValue value, QBEValue addr)
    {
        QBEInstr instr;
        instr.kind = QBEInstrKind.Store;
        instr.type = t;
        instr.args = [value, addr];
        addInstr(instr);
    }

    QBEValue load(QBEType t, QBEValue addr)
    {
        QBEValue r = tempVal(t);
        QBEInstr instr;
        instr.kind = QBEInstrKind.Load;
        instr.result = r;
        instr.type = t;
        instr.args = [addr];
        addInstr(instr);
        return r;
    }

    QBEValue call(QBEType retType, QBEValue func, QBEValue[] args)
    {
        QBEValue r = tempVal(retType);
        QBEInstr instr;
        instr.kind = QBEInstrKind.Call;
        instr.result = r;
        instr.type = retType;
        instr.args = func ~ args;
        addInstr(instr);
        return r;
    }

    void callVoid(QBEValue func, QBEValue[] args)
    {
        QBEInstr instr;
        instr.kind = QBEInstrKind.CallVoid;
        instr.args = func ~ args;
        addInstr(instr);
    }

    void ret(QBEValue value = QBEValue.init, bool isNull = false)
    {
        QBEInstr instr;
        instr.kind = QBEInstrKind.Return;
        instr.hasValue = !isNull;
        if (!isNull)
            instr.retVal = value;
        addInstr(instr);
    }

    void jmp(string target)
    {
        QBEInstr instr;
        instr.kind = QBEInstrKind.Jump;
        instr.op = target;
        addInstr(instr);
    }

    void jnz(QBEValue cond, string ifTrue, string ifFalse)
    {
        QBEInstr instr;
        instr.kind = QBEInstrKind.Jnz;
        instr.args = [cond];
        instr.op = ifTrue ~ "|" ~ ifFalse; // separador seguro
        addInstr(instr);
    }

    QBEValue cast_(QBEType toType, QBEType fromType, QBEValue value, bool s = true)
    {
        QBEValue r = tempVal(toType);
        QBEInstr instr;
        instr.kind = QBEInstrKind.Cast;
        instr.result = r;
        instr.type = toType;
        instr.fromType = fromType;
        instr.signed = s;
        instr.args = [value];
        addInstr(instr);
        return r;
    }

    QBEModule getModule()
    {
        return module_;
    }
}
