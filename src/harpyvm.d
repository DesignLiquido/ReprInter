// Harpy Virutal Machine - Baseada em registradores, leve e otimizada
// muito inspirada pela VM de Lua e pela JVM, o objetivo é se tornar backend de absolutamente qualquer linguagem de programação interpretada
// com um sistema de tipos extremamente rico suportando estruturas de dados complexas nativamente como arrays, hashtables e objects
// Fernando © 2025
module harpyvm;

@nogc:
extern(C):

import core.stdc.stdio, core.stdc.stdlib;

enum HVMType : ubyte {
    Bool, //      i1  1 byte (1 bit)
    Byte, //      i8  1 byte
    Ubyte, //     u8  1 byte
    Char, //      i8  1 byte
    Short, //     i16 2 bytes
    Ushort, //    u16 2 bytes
    Int, //       i32 4 bytes
    Uint, //      u32 4 bytes
    Long, //      i64 8 bytes
    Ulong, //     u64 8 bytes
    Float, //     f32 4 bytes
    Double,  //   f64 8 bytes
    String, //    struct HVMString
    HashTable, // struct HVMHashTable
    Object, //    struct HVMObject
}

struct HVMString {
    char* value;
    uint length;
}

struct HVMHashTable {}
struct HVMObject {}


union HVMLiteral {
    int i32;
    uint u32;
    long i64;
    ulong u64;
    byte i8; // byte e char
    ubyte u8;
    short i16;
    ushort u16;
    bool i1;
    float f32;
    double f64;
    HVMString str;
    HVMHashTable ht;
    HVMObject obj;
}

struct HVMValue {
@nogc:
    HVMType type; // 1 byte
    HVMLiteral value;

    pragma(inline, true);
    static HVMValue makeInt(int n)
    {
        HVMValue v = HVMValue(HVMType.Int);
        v.value.i32 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeUint(uint n)
    {
        HVMValue v = HVMValue(HVMType.Uint);
        v.value.u32 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeLong(long n)
    {
        HVMValue v = HVMValue(HVMType.Long);
        v.value.i64 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeUlong(ulong n)
    {
        HVMValue v = HVMValue(HVMType.Ulong);
        v.value.u64 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeShort(short n)
    {
        HVMValue v = HVMValue(HVMType.Short);
        v.value.i16 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeUshort(ushort n)
    {
        HVMValue v = HVMValue(HVMType.Ushort);
        v.value.u16 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeByte(byte n)
    {
        HVMValue v = HVMValue(HVMType.Byte);
        v.value.i8 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeUbyte(ubyte n)
    {
        HVMValue v = HVMValue(HVMType.Ubyte);
        v.value.u8 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeChar(char n)
    {
        HVMValue v = HVMValue(HVMType.Char);
        v.value.i8 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeBool(bool n)
    {
        HVMValue v = HVMValue(HVMType.Bool);
        v.value.i1 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeString(string str, uint len)
    {
        HVMValue v = HVMValue(HVMType.String);
        v.value.str = HVMString(str, len);
        return v;
    }

    pragma(inline, true);
    static HVMValue makeFloat(float n)
    {
        HVMValue v = HVMValue(HVMType.Float);
        v.value.f32 = n;
        return v;
    }

    pragma(inline, true);
    static HVMValue makeDouble(double n)
    {
        HVMValue v = HVMValue(HVMType.Double);
        v.value.f64 = n;
        return v;
    }
}

// toda instrução 4 bytes (32 bits), nada a mais
// 1 byte (8 bits) pro opcode e os outros 3 bytes pro necessário
// caso seje necessário acessar indices maior que 2^24 então uma instrução especial foi criada
// capaz de usar instruções como valores, pra carregar um valor que está em um indice muito longo necessario
// 8 bytes pro valor então o Loadkx vai lidar com isso sendo 1 instrução pro load e as outras duas instruções sendo o indice (IDX)

enum HVMOpCode : ubyte {
    // core
    Loadk, // carrega uma constante do pool
    Loadkx, // carregar uma constante com IDX grande do pool
    Call, // chamada em função normal com `ret`
    Callb, // chamada em função builtin
    Callf, // chamada em função ffi
    Ret, // retorna pro `pc` anterior
    
    // genericos pra qualquer tipo prevalecendo o tipo maior, suportam fastPath para operações com o mesmo tipo
    // prefixo B indica BitWise
    Add, // +
    Sub, // -
    Mul, // *
    Div, // /
    BShl, // >>
    BShll, // >>>
    BShr, // <<
    BXor, // ^
    BAnd, // &
    Bor, // |
    BNot, // ~
    Lt, // <
    Gt, // >
    Lte, // <=
    Gte, // >=
    Eq, // ==
    Neq, // !=
    
    Hlt, // Halt
}

struct HVM {
@nogc:
    uint* program; // programa
    uint pc; // contador do programa
    uint programSize; // tamanho do programa
    HVMValue* constantPool; // mapa de constantes
    uint constantPoolSize; // tamanho do mapa de constantes
    const ubyte STACK_LIMIT = 255;
    HVMValue[STACK_LIMIT] stack = []; // a pilha do programa
    ubyte stackSize;
    bool clean = true;
    
    this(uint* program, uint programSize, HVMValue* constantPool, uint constantPoolSize, bool clean = true)
    {
        this.program = program;
        this.programSize = programSize;
        this.constantPool = constantPool;
        this.constantPoolSize = constantPoolSize;
        this.clean = clean;
    }

    ~this() 
    {
        this.clear();
    }

    pragma(inline, true);
    void clear() 
    {
        if (program !is null)
            free(program);
        if (constantPool !is null)
            free(constantPool);
    }

    pragma(inline, true);
    void error(string msg)
    {
        printf("HVM Erro interno: %s", cast(const char*)msg);
        exit(EXIT_FAILURE);
    }

    pragma(inline, true);
    HVMValue pop()
    {
        if (stackSize < 1)
            this.error("Stack Underflow.");
        return stack[--stackSize];
    }

    pragma(inline, true);
    void push(HVMValue val)
    {
        if (stackSize == STACK_LIMIT)
            this.error("Stack Overflow.");
        stack[stackSize++] = val;
    }

    void run()
    {
        while (pc < programSize)
        {
            uint instr = program[pc];
            ubyte opcode = instr & 0xFF;

            // printf("opcode: %d\n", opcode);
            
            final switch (opcode)
            {
                case HVMOpCode.Loadk: opLoadk(instr >> 8 & 0xFFFF); pc++; continue;
                case HVMOpCode.Add: opAdd(); pc++; continue;
                case HVMOpCode.Loadkx:
                case HVMOpCode.Call:
                case HVMOpCode.Callb:
                case HVMOpCode.Callf:
                case HVMOpCode.Ret:
                case HVMOpCode.Sub:
                case HVMOpCode.Mul:
                case HVMOpCode.Div:
                case HVMOpCode.BShl:
                case HVMOpCode.BShll:
                case HVMOpCode.BShr:
                case HVMOpCode.BXor:
                case HVMOpCode.BAnd:
                case HVMOpCode.BNot:
                case HVMOpCode.Bor:
                case HVMOpCode.Lt:
                case HVMOpCode.Gt:
                case HVMOpCode.Lte:
                case HVMOpCode.Gte:
                case HVMOpCode.Eq:
                case HVMOpCode.Neq:
                case HVMOpCode.Hlt:
                    return;
            }
        }
    }

    pragma(inline, true);
    void opAdd()
    {
        HVMValue l = pop();
        HVMValue r = pop();
        // tenta fastPath
        if (l.type == r.type)
            switch (l.type)
            {
                case HVMType.Int:    push(HVMValue.makeInt(l.value.i32 + r.value.i32));                  return;
                case HVMType.Uint:   push(HVMValue.makeUint(l.value.u32 + r.value.u32));                 return;
                case HVMType.Long:   push(HVMValue.makeLong(l.value.i64 + r.value.i64));                 return;
                case HVMType.Ulong:  push(HVMValue.makeUlong(l.value.u64 + r.value.u64));                return;
                case HVMType.Char:   push(HVMValue.makeChar(cast(byte)(l.value.i8 + r.value.i8)));       return;
                case HVMType.Byte:   push(HVMValue.makeByte(cast(byte)(l.value.i8 + r.value.i8)));       return;
                case HVMType.Ubyte:  push(HVMValue.makeUbyte(cast(ubyte)(l.value.u8 + r.value.u8)));     return;
                case HVMType.Short:  push(HVMValue.makeShort(cast(short)(l.value.i16 + r.value.i16)));   return;
                case HVMType.Ushort: push(HVMValue.makeUshort(cast(ushort)(l.value.u16 + r.value.u16))); return;
                case HVMType.Float:  push(HVMValue.makeFloat(l.value.f32 + r.value.f32));                return;
                case HVMType.Double: push(HVMValue.makeDouble(l.value.f64 + r.value.f64));               return;
                default:             error("Tipo desconhecido no operação de adição.");                  return;
            }
        opAddSlowPath(l, r);
    }

    pragma(inline, true);
    void opAddSlowPath(HVMValue l, HVMValue r)
    {
        // define o tipo pelo nivel de cada tipo
        // a enum de tipos está na ordem certa
        // isso é mais que suficiente pra cast automatico
        HVMType t = l.type > r.type ? l.type : r.type;
    }

    pragma(inline, true);
    HVMValue toInt(HVMValue val)
    {
        switch (val.type)
        {
            case HVMType.Int:    return val;
            case HVMType.Uint:   return HVMValue.makeInt(cast(int)val.value.u32);
            case HVMType.Long:   return HVMValue.makeInt(cast(int)val.value.i64);
            case HVMType.Ulong:  return HVMValue.makeInt(cast(int)val.value.u64);
            case HVMType.Byte:
            case HVMType.Char:   return HVMValue.makeInt(cast(int)val.value.i8);
            case HVMType.Ubyte:  return HVMValue.makeInt(cast(int)val.value.u8);
            case HVMType.Short:  return HVMValue.makeInt(cast(int)val.value.i16);
            case HVMType.Ushort: return HVMValue.makeInt(cast(int)val.value.u16);
            case HVMType.Float:  return HVMValue.makeInt(cast(int)val.value.f32);
            case HVMType.Double: return HVMValue.makeInt(cast(int)val.value.f64);
            case HVMType.Bool:   return HVMValue.makeInt(cast(int)val.value.i1);
            default:
                error("Não é possível converter esse tipo pra um inteiro.");
                break;
        }
        // nunca é retornando porque vai dar erro antes
        return HVMValue.init;
    }

    pragma(inline, true);
    string typeToString(HVMType t)
    {
        switch (t)
        {
            case HVMType.String: return "string";
            case HVMType.Int:    return "int";
            case HVMType.Uint:   return "uint";
            case HVMType.Long:   return "long";
            case HVMType.Ulong:  return "ulong";
            case HVMType.Float:  return "float";
            case HVMType.Double: return "double";
            case HVMType.Byte:   return "byte";
            case HVMType.Ubyte:  return "ubyte";
            case HVMType.Short:  return "short";
            case HVMType.Ushort: return "ushort";
            case HVMType.Char:   return "char";
            case HVMType.Bool:   return "bool";
            default: return "<tipo desconhecido>";
        }
    }

    pragma(inline, true);
    void opLoadk(ushort idx)
    {
        if (idx > constantPoolSize || idx > stackSize || constantPoolSize == 0)
            this.error("O indice passado excede o tamanho do mapa de constantes.");
        if (stackSize == STACK_LIMIT)
            this.error("A stack já está cheia até o limite máximo, não é possivel realizar um 'Loadk'.");
        stack[stackSize++] = constantPool[idx];
    }
}
