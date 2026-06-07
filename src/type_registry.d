module type_registry;

import std.stdio, std.format, std.exception;
import htype;

class TypeRegistry
{
    private HType[string] types = [
        HTBase.Void: new HTypeBuiltin(HTBase.Void),
        HTBase.I1: new HTypeBuiltin(HTBase.I1),
        HTBase.I8: new HTypeBuiltin(HTBase.I8),
        HTBase.I16: new HTypeBuiltin(HTBase.I16),
        HTBase.I32: new HTypeBuiltin(HTBase.I32),
        HTBase.I64: new HTypeBuiltin(HTBase.I64),
        HTBase.U8: new HTypeBuiltin(HTBase.U8),
        HTBase.U16: new HTypeBuiltin(HTBase.U16),
        HTBase.U32: new HTypeBuiltin(HTBase.U32),
        HTBase.U64: new HTypeBuiltin(HTBase.U64),
        HTBase.F32: new HTypeBuiltin(HTBase.F32),
        HTBase.F64: new HTypeBuiltin(HTBase.F64),
    ];

    bool setType(string type, HType t)
    {
        if (exists(type))
            return false;
        types[type] = t;
        return true;
    }

    HType* getType(string type)
    {
        return type in types;
    }

    bool exists(string type)
    {
        return getType(type) !is null;
    }
}
