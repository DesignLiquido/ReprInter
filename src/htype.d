module htype;

import ast;

enum HTypeKind : ubyte
{
    Builtin,
    Struct,
}

enum HTBase : string
{
    Void = "void",
    I1 = "i1",
    I8 = "i8",
    I16 = "i16",
    I32 = "i32",
    I64 = "i64",
    U8 = "u8",
    U16 = "u16",
    U32 = "u32",
    U64 = "u64",
    F32 = "f32",
    F64 = "f64",
}

abstract class HType
{
    HTypeKind kind;
    uint getSize(); // em bytes
    string toStr();

    this(HTypeKind kind)
    {
        this.kind = kind;
    }
}

class HTypeBuiltin : HType
{
    HTBase base;

    this(HTBase base)
    {
        super(HTypeKind.Builtin);
        this.base = base;
    }

    override string toStr()
    {
        return base;
    }

    override uint getSize()
    {
        final switch (base) with (HTBase)
        {
        case Void:
            return 0;
        case I1:
        case I8:
        case U8:
            return 1;
        case I16:
        case U16:
            return 2;
        case I32:
        case F32:
        case U32:
            return 4;
        case I64:
        case U64:
        case F64:
            return 8;
        }
    }
}

class HTypeStruct : HType
{
    string name;
    StructField[string] fields;
    uint size;

    this(string name, StructField[string] fields)
    {
        super(HTypeKind.Struct);
        this.name = name;
        this.fields = fields;
    }

    override string toStr()
    {
        return name;
    }

    override uint getSize()
    {
        return size;
    }
}
