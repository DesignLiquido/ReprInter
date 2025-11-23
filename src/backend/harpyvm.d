module backend.harpyvm;
import std.stdio, std.variant, std.conv, std.datetime.stopwatch, std.string, std.algorithm;
import core.stdc.stdio, core.stdc.string, core.stdc.stdlib, core.sys.posix.dlfcn, core
    .stdc.string : strlen;

enum OpCode : ubyte
{
    // Builtin
    PRINT,
    PRINTI, // print int
    PRINTD, // print double
    PRINTS, // print string
    PRINTB, // print bool
    INPUT,

    // Math operations {{
    // long
    ADDI,
    SUBI,
    MULI,
    DIVI,
    MODI,
    // opcodes para otimizar calculo
    PPADDI, // push push addi
    PPSUBI, // push push subi
    PPMULI, // push push muli
    PPDIVI, // push push divi
    PPMODI, // push push modi
    // double
    ADDF,
    SUBF,
    MULF,
    DIVF,
    MODF,
    // opcodes para otimizar calculo
    PPADDF, // push push addf
    PPSUBF, // push push subf
    PPMULF, // push push mulf
    PPDIVF, // push push divf
    PPMODF, // push push modf

    // operações que podem ser mais lentas mas extremamente poderosas {{
    ADD, // detecta tipo e soma
    SUB, // detecta tipo e subtrai
    MUL, // detecta tipo e multiplica
    DIV, // detecta tipo e divide
    MOD, // detecta tipo e módulo

    // Versões otimizadas polimórficas
    PPADD, // push push add
    PPSUB, // push push sub
    PPMUL, // push push mul
    PPDIV, // push push div
    PPMOD, // push push mod
    // }}

    AND, // &
    OR, // |
    XOR, // ^
    NOT, // ~
    SHR, // >>
    SHL, //<<
    SAR, // >>>
    // }}

    // Jumps
    JMP,
    JZ,
    JNZ,

    // Comparativos
    LT,
    LE,
    LTE,
    GT,
    GE,
    GTE,
    EQ,
    NE,
    BBEQ, // bool bool == = true && true
    BBNE, // bool bool != = true || true

    // Load/Store stack and heap
    LOADL, // LOAD_LOCAL    = stack
    STOREL, // STORE_LOCAL  = stack
    LOADG, // LOAD_GLOBAL   = heap
    STOREG, // STORE_GLOBAL = heap

    // Arrays
    ARRN, // array new
    ARRG, // array get
    ARRS, // array set
    ARRL, // array length
    ARRP, // array push
    ARRPP, // array pop

    // Structs
    STRUCTN, // struct new (cria uma nova struct)
    STRUCTG, // struct get (obtem o field de uma struct)
    STRUCTS, // struct set (seta um novo valor no field de uma struct)

    // Enums
    ENUMN, // enum new (cria uma nova enum)
    ENUMG, // enum get (obtem o field de uma enum)

    // Strings
    STRL, // string length
    STRG, // string get
    STRP, // string push

    // FFI
    FFIL, // FFI Load
    FFILI, // FFI Load Inteligente
    FFIC, // FFI Call

    // Casts (conversões)
    STOF, // string to float
    ITOF, // int to float
    STOI, // string to int

    // Core
    PUSH,
    POP,
    CALL,
    DUP,
    TRAW, // type raw (retorna uma string com o nome do tipo)
    EXIT,
    RET,
    HALT
}

enum Type
{
    String,
    Int,
    Float,
    Bool,
    Array,
    Struct,
    Enum,
}

// para ffi {{
union FFIRawValue
{
    char* str; //          string
    long i64; //           int
    double f64; //         float
    bool i1; //            bool
    FFIValue* array; //    array
    FFIValue* struct_; //  struct
    FFIValue* enum_; //    enum
}

struct FFIValue
{
    Type type;
    FFIRawValue value;
    long len;
}

struct FFICallParams
{
    FFIValue* args;
    ulong argc;
}
// }}

union EValue
{
    string str; //      string
    long i64; //        int
    double f64; //      float
    bool i1; //         bool
    Value[] array; //   array
    Value[] struct_; // struct
    Value[] enum_; //   enum
}

struct Value
{
    Type type;
    EValue value;
    long len;
}

struct Instruction
{
    OpCode op;
    Value val;
}

struct StackFrame
{
    Value[string] stack;
    long returnAddr;
}

struct StructDef
{
    string name;
    string[] fieldNames;
    Type[] fieldTypes;
}

alias ffi_extern_function = FFIValue function(FFICallParams*);

class HarpyVM
{
    Value[] valueStack; // global stack for temp values
    StackFrame[] frameStack;
    Value[string] heap;
    Instruction[] code;
    long pc; // program counter
    void*[string] libs;
    ffi_extern_function[string] externalFunctions;
    StructDef[string] structDefs; // definições de structs

    this()
    {
        // frame global -> main
        frameStack ~= StackFrame();
    }

    pragma(inline, true);
    void push(Value v)
    {
        valueStack ~= v;
    }

    pragma(inline, true);
    Value pop()
    {
        if (valueStack.length == 0)
            throw new Exception("Harpy Virtual Machine Error - Stack underflow");
        auto v = valueStack[$ - 1];
        valueStack.length--;
        return v;
    }

    pragma(inline, true);
    Value peek()
    {
        if (valueStack.length == 0)
            throw new Exception("Harpy Virtual Machine Error - Stack underflow");
        return valueStack[$ - 1];
    }

    pragma(inline, true);
    ref Value peekRef()
    {
        if (valueStack.length == 0)
            throw new Exception("Harpy Virtual Machine Error - Stack underflow");
        return valueStack[$ - 1];
    }

    ref StackFrame currentFrame()
    {
        return frameStack[$ - 1];
    }

    pragma(inline, true);
    Value makeInt(long i)
    {
        EValue ev;
        ev.i64 = i;
        return Value(Type.Int, ev);
    }

    pragma(inline, true);
    Value makeStr(string s)
    {
        EValue ev;
        ev.str = s;
        return Value(Type.String, ev);
    }

    pragma(inline, true);
    Value makeFloat(double f)
    {
        EValue ev;
        ev.f64 = f;
        return Value(Type.Float, ev);
    }

    pragma(inline, true);
    Value makeBool(bool b)
    {
        EValue ev;
        ev.i1 = b;
        return Value(Type.Bool, ev);
    }

    pragma(inline, true);
    Value makeArray(Value[] arr)
    {
        EValue ev;
        ev.array = arr;
        return Value(Type.Array, ev, arr.length);
    }

    pragma(inline, true);
    Value makeStruct(Value[] struct_)
    {
        EValue ev;
        ev.struct_ = struct_;
        return Value(Type.Struct, ev, struct_.length);
    }

    pragma(inline, true);
    Value makeEnum(Value[] enm)
    {
        EValue ev;
        ev.enum_ = enm;
        return Value(Type.Enum, ev, enm.length);
    }

    void run()
    {
        pc = 0;
        while (pc < code.length)
        {
            Instruction inst = code[pc];
            // writeln("OPCODE: ", to!string(inst.op));
            switch (inst.op)
            {
            case OpCode.PUSH:
                push(inst.val);
                pc++;
                break;

            case OpCode.POP:
                pop();
                pc++;
                break;

            case OpCode.DUP:
                Value v = pop();
                push(deepCopy(v));
                pc++;
                break;

            case OpCode.ADDI:
                long b = pop().value.i64;
                long a = pop().value.i64;
                push(makeInt(a + b));
                pc++;
                break;

            case OpCode.SUBI:
                long b = pop().value.i64;
                long a = pop().value.i64;
                push(makeInt(a - b));
                pc++;
                break;

            case OpCode.MULI:
                long b = pop().value.i64;
                long a = pop().value.i64;
                push(makeInt(a * b));
                pc++;
                break;

            case OpCode.DIVI:
                long b = pop().value.i64;
                long a = pop().value.i64;
                push(makeInt(a / b));
                pc++;
                break;

            case OpCode.MODI:
                long b = pop().value.i64;
                long a = pop().value.i64;
                push(makeInt(a % b));
                pc++;
                break;

            case OpCode.ADDF:
                double b = pop().value.f64;
                double a = pop().value.f64;
                push(makeFloat(a + b));
                pc++;
                break;

            case OpCode.SUBF:
                double b = pop().value.f64;
                double a = pop().value.f64;
                push(makeFloat(a - b));
                pc++;
                break;

            case OpCode.MULF:
                double b = pop().value.f64;
                double a = pop().value.f64;
                push(makeFloat(a * b));
                pc++;
                break;

            case OpCode.DIVF:
                double b = pop().value.f64;
                double a = pop().value.f64;
                push(makeFloat(a / b));
                pc++;
                break;

            case OpCode.MODF:
                double b = pop().value.f64;
                double a = pop().value.f64;
                push(makeFloat(a % b));
                pc++;
                break;

            case OpCode.ADD:
                Value b = pop();
                Value a = pop();
                if (a.type == Type.Int && b.type == Type.Int)
                    push(makeInt(a.value.i64 + b.value.i64));
                else if (a.type == Type.Float && b.type == Type.Float)
                    push(makeFloat(a.value.f64 + b.value.f64));
                else if (a.type == Type.Int && b.type == Type.Float)
                    push(makeFloat(to!double(a.value.i64) + b.value.f64));
                else if (a.type == Type.Float && b.type == Type.Int)
                    push(makeFloat(a.value.f64 + to!double(b.value.i64)));
                else
                    throw new Exception("Tipos incompatíveis para ADD");
                pc++;
                break;

            case OpCode.SUB:
                Value b = pop();
                Value a = pop();
                if (a.type == Type.Int && b.type == Type.Int)
                    push(makeInt(a.value.i64 - b.value.i64));
                else if (a.type == Type.Float && b.type == Type.Float)
                    push(makeFloat(a.value.f64 - b.value.f64));
                else if (a.type == Type.Int && b.type == Type.Float)
                    push(makeFloat(to!double(a.value.i64) - b.value.f64));
                else if (a.type == Type.Float && b.type == Type.Int)
                    push(makeFloat(a.value.f64 - to!double(b.value.i64)));
                else
                    throw new Exception("Tipos incompatíveis para SUB");
                pc++;
                break;

            case OpCode.MUL:
                Value b = pop();
                Value a = pop();
                if (a.type == Type.Int && b.type == Type.Int)
                    push(makeInt(a.value.i64 * b.value.i64));
                else if (a.type == Type.Float && b.type == Type.Float)
                    push(makeFloat(a.value.f64 * b.value.f64));
                else if (a.type == Type.Int && b.type == Type.Float)
                    push(makeFloat(to!double(a.value.i64) * b.value.f64));
                else if (a.type == Type.Float && b.type == Type.Int)
                    push(makeFloat(a.value.f64 * to!double(b.value.i64)));
                else
                    throw new Exception("Tipos incompatíveis para MUL");
                pc++;
                break;

            case OpCode.DIV:
                Value b = pop();
                Value a = pop();
                if (a.type == Type.Int && b.type == Type.Int)
                {
                    if (b.value.i64 == 0)
                        throw new Exception("Divisão por zero");
                    push(makeInt(a.value.i64 / b.value.i64));
                }
                else if (a.type == Type.Float && b.type == Type.Float)
                {
                    if (b.value.f64 == 0.0)
                        throw new Exception("Divisão por zero");
                    push(makeFloat(a.value.f64 / b.value.f64));
                }
                else if (a.type == Type.Int && b.type == Type.Float)
                {
                    if (b.value.f64 == 0.0)
                        throw new Exception("Divisão por zero");
                    push(makeFloat(to!double(a.value.i64) / b.value.f64));
                }
                else if (a.type == Type.Float && b.type == Type.Int)
                {
                    if (b.value.i64 == 0)
                        throw new Exception("Divisão por zero");
                    push(makeFloat(a.value.f64 / to!double(b.value.i64)));
                }
                else
                    throw new Exception("Tipos incompatíveis para DIV");
                pc++;
                break;

            case OpCode.MOD:
                Value b = pop();
                Value a = pop();
                if (a.type == Type.Int && b.type == Type.Int)
                {
                    if (b.value.i64 == 0)
                        throw new Exception("Módulo por zero");
                    push(makeInt(a.value.i64 % b.value.i64));
                }
                else if (a.type == Type.Float && b.type == Type.Float)
                {
                    if (b.value.f64 == 0.0)
                        throw new Exception("Módulo por zero");
                    push(makeFloat(a.value.f64 % b.value.f64));
                }
                else if (a.type == Type.Int && b.type == Type.Float)
                {
                    if (b.value.f64 == 0.0)
                        throw new Exception("Módulo por zero");
                    push(makeFloat(cast(double) a.value.i64 % b.value.f64));
                }
                else if (a.type == Type.Float && b.type == Type.Int)
                {
                    if (b.value.i64 == 0)
                        throw new Exception("Módulo por zero");
                    push(makeFloat(a.value.f64 % cast(double) b.value.i64));
                }
                else
                    throw new Exception("Tipos incompatíveis para MOD");
                pc++;
                break;

            case OpCode.AND:
                Value v2 = pop();
                Value v1 = pop();
                push(makeInt(v1.value.i64 & v2.value.i64));
                pc++;
                break;

            case OpCode.OR:
                Value v2 = pop();
                Value v1 = pop();
                push(makeInt(v1.value.i64 | v2.value.i64));
                pc++;
                break;

            case OpCode.XOR:
                Value v2 = pop();
                Value v1 = pop();
                push(makeInt(v1.value.i64 ^ v2.value.i64));
                pc++;
                break;

            case OpCode.NOT:
                Value v1 = pop();
                push(makeInt(~v1.value.i64));
                pc++;
                break;

            case OpCode.SHR:
                Value v2 = pop();
                Value v1 = pop();
                push(makeInt(v1.value.i64 >> v2.value.i64));
                pc++;
                break;

            case OpCode.SHL:
                Value v2 = pop();
                Value v1 = pop();
                push(makeInt(v1.value.i64 << v2.value.i64));
                pc++;
                break;

            case OpCode.SAR:
                Value v2 = pop();
                Value v1 = pop();
                push(makeInt(v1.value.i64 >>> v2.value.i64));
                pc++;
                break;

            case OpCode.LOADL:
                string name = inst.val.value.str;
                // writeln("LOADL: ", name);
                push(currentFrame().stack[name]);
                pc++;
                break;

            case OpCode.STOREL:
                string name = inst.val.value.str;
                Value val = pop();
                // writeln(name, " = ", val);
                currentFrame().stack[name] = val;
                pc++;
                break;

            case OpCode.LOADG:
                string name = inst.val.value.str;
                push(heap[name]);
                pc++;
                break;

            case OpCode.STOREG:
                string name = inst.val.value.str;
                heap[name] = pop();
                pc++;
                break;

            case OpCode.JMP:
                pc = inst.val.value.i64;
                break;

            case OpCode.JZ:
                long cond = pop().value.i64;
                if (cond == 0)
                    pc = inst.val.value.i64;
                else
                    pc++;
                break;

            case OpCode.JNZ:
                long cond = pop().value.i64;
                if (cond != 0)
                    pc = inst.val.value.i64;
                else
                    pc++;
                break;

            case OpCode.LT:
                Value b = pop();
                Value a = pop();
                // writeln("LT: ", a, " < ", b);
                if (a.type == Type.Int && b.type == Type.Int)
                    push(makeBool(a.value.i64 < b.value.i64 ? 1 : 0));
                else if (a.type == Type.Float && b.type == Type.Float)
                    push(makeBool(a.value.f64 < b.value.f64 ? 1 : 0));
                else if (a.type == Type.String && b.type == Type.String)
                    push(makeBool(a.value.str < b.value.str ? 1 : 0));
                else
                    push(makeBool(0)); // tipos incompatíveis
                pc++;
                break;

            case OpCode.LTE:
                Value b = pop();
                Value a = pop();
                // writeln("LTE: ", a, " <= ", b);
                if (a.type == Type.Int && b.type == Type.Int)
                    push(makeBool(a.value.i64 <= b.value.i64 ? 1 : 0));
                else if (a.type == Type.Float && b.type == Type.Float)
                    push(makeBool(a.value.f64 <= b.value.f64 ? 1 : 0));
                else if (a.type == Type.String && b.type == Type.String)
                    push(makeBool(a.value.str <= b.value.str ? 1 : 0));
                else
                    push(makeBool(0));
                pc++;
                break;

            case OpCode.GT:
                Value b = pop();
                Value a = pop();
                // writeln("GT: ", a, " > ", b);
                if (a.type == Type.Int && b.type == Type.Int)
                    push(makeBool(a.value.i64 > b.value.i64 ? 1 : 0));
                else if (a.type == Type.Float && b.type == Type.Float)
                    push(makeBool(a.value.f64 > b.value.f64 ? 1 : 0));
                else if (a.type == Type.String && b.type == Type.String)
                    push(makeBool(a.value.str > b.value.str ? 1 : 0));
                else
                    push(makeBool(0));
                pc++;
                break;

            case OpCode.GTE:
                Value b = pop();
                Value a = pop();
                // writeln("GTE: ", a, " >= ", b);
                if (a.type == Type.Int && b.type == Type.Int)
                    push(makeBool(a.value.i64 >= b.value.i64 ? 1 : 0));
                else if (a.type == Type.Float && b.type == Type.Float)
                    push(makeBool(a.value.f64 >= b.value.f64 ? 1 : 0));
                else if (a.type == Type.String && b.type == Type.String)
                    push(makeBool(a.value.str >= b.value.str ? 1 : 0));
                else
                    push(makeBool(0));
                pc++;
                break;

            case OpCode.EQ:
                Value b = pop();
                Value a = pop();
                // writefln("DEBUG EQ: LEFT = %d EQ RIGHT = %d\n", a.value.i1, b.value.i1);
                if (a.type == Type.Int && b.type == Type.Int)
                    push(makeBool(a.value.i64 == b.value.i64 ? 1 : 0));
                else if (a.type == Type.Float && b.type == Type.Float)
                    push(makeBool(a.value.f64 == b.value.f64 ? 1 : 0));
                else if (a.type == Type.String && b.type == Type.String)
                    push(makeBool(a.value.str == b.value.str ? 1 : 0));
                else if (a.type == Type.Bool && b.type == Type.Bool)
                    push(makeBool(a.value.i64 == b.value.i64 ? 1 : 0));
                else
                    push(makeBool(0));
                pc++;
                break;

            case OpCode.NE:
                Value b = pop();
                Value a = pop();
                if (a.type == Type.Int && b.type == Type.Int)
                    push(makeBool(a.value.i64 != b.value.i64 ? 1 : 0));
                else if (a.type == Type.Float && b.type == Type.Float)
                    push(makeBool(a.value.f64 != b.value.f64 ? 1 : 0));
                else if (a.type == Type.String && b.type == Type.String)
                    push(makeBool(a.value.str != b.value.str ? 1 : 0));
                else if (a.type == Type.Bool && b.type == Type.Bool)
                    push(makeBool(a.value.i64 != b.value.i64 ? 1 : 0));
                else
                    push(makeBool(1));
                pc++;
                break;

            case OpCode.BBEQ: // Boolean Binary Equal = AND lógico
                Value right = pop();
                Value left = pop();
                // writefln("DEBUG BBEQ: LEFT = %d AND RIGHT = %d\n", left.value.i1, right.value.i1);
                push(makeBool(left.value.i1 && right.value.i1 ? 1 : 0));
                pc++;
                break;

            case OpCode.BBNE: // Boolean Binary Not Equal = OR lógico
                Value right = pop();
                Value left = pop();
                // writefln("DEBUG BBNE: LEFT = %d OR RIGHT = %d\n", left.value.i1, right.value.i1);
                push(makeBool(left.value.i1 || right.value.i1 ? 1 : 0));
                pc++;
                break;

            case OpCode.ARRN: // array new
                long size = pop().value.i64;
                Value[] arr;
                for (long i = size - 1; i >= 0; i--)
                    arr ~= pop();
                push(this.makeArray(arr));
                pc++;
                break;

            case OpCode.ARRG: // array get (idx)
                long idx = pop().value.i64;
                Value val = pop();
                // não faz pop pra garantir que não fique copiando os arrays
                Value[] arr = val.value.array;
                // writeln(val, " ", idx);
                if (idx >= arr.length)
                    throw new Exception("O indice acessado é maior do que o tamanho do vetor.");
                push(arr[idx]);
                pc++;
                break;

                // case OpCode.ARRS: // array set -> arr[idx] = n
                //     // pra ser mais otimizado
                //     Value val = pop();
                //     long idx = pop().value.i64;
                //     // Value[] arr = pop().value.array;
                //     // não faça pop, faça o peek e altere
                //     Value[] arr = pop().value.array;
                //     if (idx >= arr.length)
                //         throw new Exception("O indice acessado é maior do que o tamanho do vetor.");
                //     arr[idx] = val;
                //     // nem precisa de push
                //     // alterou diretamente na memoria
                //     // push(arr);
                //     pc++;
                //     break;
            case OpCode.ARRS: // array set -> arr[idx] = n
                Value val = pop();
                long idx = pop().value.i64;

                if (valueStack.length == 0)
                    throw new Exception("Stack underflow em ARRS");

                if (valueStack[$ - 1].type != Type.Array)
                    throw new Exception("ARRS requer um Array");

                if (idx >= valueStack[$ - 1].value.array.length)
                    throw new Exception("O indice acessado é maior do que o tamanho do vetor.");

                // Modifica diretamente na stack
                valueStack[$ - 1].value.array[idx] = val;
                //pop(); // Remove o array da stack após modificação
                pc++;
                break;

            case OpCode.ARRL: // array length
                // não precisa fazer pop, apenas visualize ele e retorne a informação
                Value[] arr = pop().value.array;
                push(this.makeInt(arr.length));
                pc++;
                break;

            case OpCode.ARRP: // array push -> arr ~= n
                Value val = pop();
                Value[] arr = pop().value.array;
                arr ~= val;
                push(makeArray(arr));
                pc++;
                break;

            case OpCode.ARRPP: // array pop -> remove último elemento e retorna o array modificado
                if (valueStack.length == 0)
                    throw new Exception("Stack underflow em ARRPP");

                if (valueStack[$ - 1].type != Type.Array)
                    throw new Exception("ARRPP só pode ser usado em vetores.");

                if (valueStack[$ - 1].value.array.length == 0)
                    throw new Exception("Não é possível fazer pop de um array vazio");

                // Remove o último elemento do array
                valueStack[$ - 1].value.array = valueStack[$ - 1].value.array[0 .. $ - 1];
                valueStack[$ - 1].len = cast(long) valueStack[$ - 1].value.array.length;

                // Não precisa de pop adicional - o array modificado já está no topo da stack
                pc++;
                break;

            case OpCode.STRUCTN: // struct new
                long size = inst.val.value.i64;
                Value[] struct_;
                for (long i = size - 1; i >= 0; i--)
                    struct_ ~= pop();
                push(this.makeStruct(struct_));
                pc++;
                break;

            case OpCode.STRUCTG: // struct get (field)
                long idx = inst.val.value.i64;
                Value val = pop();
                // writeln("STRUCTG: ", val);
                // writeln("STRUCTG IDX: ", idx);
                Value[] strc = val.value.struct_;
                // writeln("STRUCTG VALUES: ", strc);
                push(strc[idx]);
                pc++;
                break;

                // case OpCode.STRUCTS: // struct set -> struct.field = n
                //     Value val = pop();
                //     Value val2 = pop();
                //     Value[] strc = val2.value.struct_;
                //     long idx = inst.val.value.i64;
                //     strc[idx] = val;
                //     push(this.makeStruct(strc));
                //     pc++;
                //     break;

            case OpCode.STRUCTS: // struct set -> struct.field = n
                Value val = pop(); // novo valor
                long idx = inst.val.value.i64;

                if (valueStack.length == 0)
                    throw new Exception("Stack underflow em STRUCTS");

                if (valueStack[$ - 1].type != Type.Struct)
                    throw new Exception("STRUCTS requer um Struct no topo da stack");

                if (idx >= valueStack[$ - 1].value.struct_.length)
                    throw new Exception("Índice de field inválido");

                // Modifica diretamente na stack
                valueStack[$ - 1].value.struct_[idx] = val;
                pc++;
                break;

            case OpCode.ENUMN: // enum new
                long size = inst.val.value.i64;
                Value[] enm;
                for (long i = size - 1; i >= 0; i--)
                    enm ~= pop();
                push(this.makeEnum(enm));
                pc++;
                break;

            case OpCode.ENUMG: // enum get (field)
                long idx = inst.val.value.i64;
                Value[] enm = pop().value.enum_;
                push(enm[idx]);
                pc++;
                break;

            case OpCode.CALL:
                StackFrame newFrame; // Cria novo stack frame
                newFrame.returnAddr = pc + 1;
                frameStack ~= newFrame;
                pc = inst.val.value.i64; // Jump para a função
                break;

            case OpCode.RET:
                if (frameStack.length <= 1)
                    throw new Exception("Cannot return from global frame");
                long returnAddr = currentFrame().returnAddr;
                frameStack.length--;
                pc = returnAddr;
                break;

            case OpCode.STRL: // string length
                string str = pop().value.str;
                push(this.makeInt(str.length));
                pc++;
                break;

            case OpCode.STRG: // ""[idx]
                long idx = pop().value.i64;
                string str = pop().value.str;
                if (idx >= str.length)
                    throw new Exception("O indice acessado é maior do que o tamanho do texto.");
                push(this.makeStr(to!string(str[idx])));
                pc++;
                break;

            case OpCode.STRP: // string push
                string str_ = pop().value.str;
                string str = pop().value.str;
                push(this.makeStr(str ~ str_));
                pc++;
                break;

            case OpCode.STOI:
                push(makeInt(to!long(pop().value.str)));
                pc++;
                break;

            case OpCode.STOF:
                push(makeFloat(to!double(pop().value.str)));
                pc++;
                break;

            case OpCode.ITOF:
                push(makeFloat(to!double(pop().value.i64)));
                pc++;
                break;

            case OpCode.TRAW:
                string type = "";
                Type ty = pop().type;
                final switch (ty)
                {
                case Type.Int:
                    type = "inteiro";
                    break;
                case Type.Float:
                    type = "decimal";
                    break;
                case Type.String:
                    type = "texto";
                    break;
                case Type.Struct:
                    type = "estrutura";
                    break;
                case Type.Enum:
                    type = "enum";
                    break;
                case Type.Array:
                    type = "vetor";
                    break;
                case Type.Bool:
                    type = "logico";
                    break;
                }
                push(this.makeStr(type));
                pc++;
                break;

            case OpCode.FFIL: // FFI Load
                string libpath = pop().value.str;
                string libname = inst.val.value.str;
                if (libpath !in libs)
                {
                    void* handle = dlopen(libpath.toStringz, RTLD_LAZY);
                    if (!handle)
                    {
                        writefln("Erro ao carregar %s:", libname);
                        writeln(dlerror().fromStringz);
                        throw new Exception("Falha ao carregar biblioteca: " ~ libname);
                    }
                    libs[libname] = handle;
                }
                pc++;
                break;

            case OpCode.FFILI: // FFI Load Inteligente
                pc++;
                break;

            case OpCode.FFIC: // FFI Call
                string funcname = pop().value.str;
                string libname = pop().value.str;
                long argc = pop().value.i64;

                void* handle = null;

                if (libname in libs)
                    handle = libs[libname];

                if (!handle) // writefln("Erro ao carregar %s:", libname); // writeln("Erro: ", dlerror().fromStringz);
                    throw new Exception("Falha ao carregar biblioteca: " ~ libname);

                ffi_extern_function funcPtr;
                if (funcname !in externalFunctions)
                    funcPtr = cast(ffi_extern_function) dlsym(handle, funcname.toStringz);
                else
                    funcPtr = externalFunctions[funcname];

                if (!funcPtr)
                    throw new Exception("Simbolo não encontrado: " ~ funcname);

                // converter argumentos para C
                FFIValue* args = cast(FFIValue*) malloc(argc * FFIValue.sizeof);
                for (long i; i < argc; i++)
                {
                    FFIValue ffi = valueToFFIValue(pop());
                    FFIRawValue cffi = ffi.value;
                    args[i].type = ffi.type;
                    args[i].value = *cast(FFIRawValue*)&cffi;
                }

                FFICallParams p = FFICallParams(args, argc);
                // chama a função
                FFIValue result = funcPtr(&p); // passe o endereço diretamente
                // converter resultado de volta
                Value vmResult = ffiValueToValue(result);

                // liberação de memoria aprimorada
                freeFfiValue(result);

                for (long i = 0; i < argc; i++)
                    freeFfiValue(args[i]);

                free(args);
                push(vmResult);
                pc++;
                break;

            case OpCode.PRINT:
                Value v = pop();
                final switch (v.type)
                {
                case Type.Int:
                    write(v.value.i64);
                    break;
                case Type.Float:
                    write(v.value.f64);
                    break;
                case Type.String:
                    write(v.value.str);
                    break;
                case Type.Bool:
                    write(v.value.i1 ? "verdadeiro" : "falso");
                    break;
                case Type.Array:
                    write("<Array>");
                    break;
                case Type.Struct:
                    write("<Struct>");
                    break;
                case Type.Enum:
                    write("<Enum>");
                    break;
                }
                pc++;
                break;

            case OpCode.PRINTI:
                Value val = pop();
                if (val.type != Type.Int)
                    throw new Exception("PRINTI esperava um inteiro.");
                write(val.value.i64);
                pc++;
                break;

            case OpCode.PRINTD:
                Value val2 = pop();
                Value val1 = pop();
                if (val1.type != Type.Float)
                    throw new Exception("PRINTF esperava um decimal.");
                if (val2.type != Type.Int)
                    throw new Exception("PRINTI esperava um inteiro.");
                writef(format("%%.%df", val2.value.i64), val1.value.f64);
                pc++;
                break;

            case OpCode.PRINTS:
                Value val = pop();
                if (val.type != Type.String)
                    throw new Exception("PRINTS esperava um texto.");
                write(val.value.str);
                pc++;
                break;

            case OpCode.PRINTB:
                Value val = pop();
                if (val.type != Type.Bool)
                    throw new Exception("PRINTB esperava um logico.");
                write(val.value.i1);
                pc++;
                break;

            case OpCode.INPUT:
                string str = readln().strip();
                push(makeStr(str));
                pc++;
                break;

            case OpCode.EXIT:
                exit(to!int(pop().value.i64));
                return;
            case OpCode.HALT:
                return;
            default:
                throw new Exception(
                    "Harpy Virtual Machine Error - OpCode inválido: " ~ to!string(inst.op));
            }
        }
    }

    void freeFfiValue(FFIValue ffi)
    {
        final switch (ffi.type)
        {
        case Type.String:
            if (ffi.value.str !is null)
                free(ffi.value.str);
            break;

        case Type.Array:
            if (ffi.value.array !is null)
            {
                for (long i = 0; i < ffi.len; ++i)
                    freeFfiValue(ffi.value.array[i]);
                free(ffi.value.array);
            }
            break;

        case Type.Struct:
            if (ffi.value.struct_ !is null)
            {
                for (long i = 0; i < ffi.len; ++i)
                    freeFfiValue(ffi.value.struct_[i]);
                free(ffi.value.struct_);
            }
            break;

        case Type.Bool:
        case Type.Int:
        case Type.Float:
        case Type.Enum:
            // Nada para liberar
            break;
        }
    }

    FFIValue valueToFFIValue(Value value)
    {
        FFIValue ffi;
        ffi.type = value.type;
        ffi.len = value.len;

        final switch (value.type)
        {
        case Type.Bool:
            ffi.value.i1 = value.value.i1;
            break;

        case Type.Int:
            ffi.value.i64 = value.value.i64;
            break;

        case Type.Float:
            ffi.value.f64 = value.value.f64;
            break;

        case Type.String:
            if (value.value.str.length > 0)
                ffi.value.str = strdup(value.value.str.toStringz);
            else
                ffi.value.str = null;
            break;

        case Type.Array:
            {
                auto arr = value.value.array;
                size_t len = arr.length;
                ffi.len = cast(long) len;

                if (len == 0)
                {
                    ffi.value.array = null;
                    break;
                }

                FFIValue* farr = cast(FFIValue*) malloc(len * FFIValue.sizeof);
                if (farr is null)
                    throw new Exception("malloc fail in valueToFFIValue (array)");

                for (size_t i = 0; i < len; ++i)
                    farr[i] = valueToFFIValue(arr[i]);

                ffi.value.array = farr;
                break;
            }

        case Type.Struct:
            {
                auto s = value.value.struct_;
                long len = cast(long) s.length;
                ffi.len = len;

                if (len == 0)
                {
                    ffi.value.struct_ = null;
                    break;
                }

                FFIValue* fstruct = cast(FFIValue*) malloc(len * FFIValue.sizeof);
                if (fstruct is null)
                    throw new Exception("malloc fail in valueToFFIValue (struct)");

                for (size_t i = 0; i < len; ++i)
                    fstruct[i] = valueToFFIValue(s[i]);

                ffi.value.struct_ = fstruct;
                break;
            }

        case Type.Enum:
            break;
        }

        return ffi;
    }

    Value deepCopy(Value v)
    {
        final switch (v.type)
        {
        case Type.Int:
        case Type.Float:
        case Type.Bool:
        case Type.String:
            return v; // Tipos simples podem ser copiados diretamente

        case Type.Array:
            Value[] newArr;
            foreach (elem; v.value.array)
                newArr ~= deepCopy(elem); // Recursivo
            return makeArray(newArr);

        case Type.Struct:
            Value[] newStruct;
            foreach (field; v.value.struct_)
                newStruct ~= deepCopy(field); // Recursivo
            return makeStruct(newStruct);

        case Type.Enum:
            Value[] newEnum;
            foreach (field; v.value.enum_)
                newEnum ~= deepCopy(field);
            return makeEnum(newEnum);
        }
    }

    Value ffiValueToValue(FFIValue ffi)
    {
        Value value;
        value.type = ffi.type;
        value.len = ffi.len;

        final switch (ffi.type)
        {
        case Type.Bool:
            value.value.i1 = ffi.value.i1;
            break;

        case Type.Int:
            value.value.i64 = ffi.value.i64;
            break;

        case Type.Float:
            value.value.f64 = ffi.value.f64;
            break;

        case Type.String:
            if (ffi.value.str !is null)
            {
                // cria uma cópia gerenciada pelo GC do D
                size_t len = strlen(ffi.value.str);
                value.value.str = ffi.value.str[0 .. len].idup;
            }
            else
                value.value.str = "";
            break;

        case Type.Array:
            {
                long n = ffi.len;
                if (n <= 0 || ffi.value.array is null)
                {
                    value.value.array = [];
                    break;
                }

                value.value.array = [];
                value.value.array.reserve(n);

                FFIValue* parr = ffi.value.array;
                for (long i = 0; i < n; ++i)
                    value.value.array ~= ffiValueToValue(parr[i]);

                break;
            }

        case Type.Struct:
            {
                long len = ffi.len;

                if (len <= 0 || ffi.value.struct_ is null)
                {
                    value.value.struct_ = [];
                    break;
                }

                value.value.struct_ = [];
                value.value.struct_.reserve(len);

                FFIValue* pstruct = ffi.value.struct_;
                for (long i = 0; i < len; ++i)
                    value.value.struct_ ~= ffiValueToValue(pstruct[i]);

                break;
            }

        case Type.Enum:
            break;
        }

        return value;
    }
}

class HarpyCG
{
private:
    HarpyVM engine;
    int[] callPatchIndices; // indices in program that need to be patched
    string[] callPatchNames; // corresponding label names to patch

public:
    Instruction[] program;
    int[string] labels; // label -> address (index in program)

    this(HarpyVM eng)
    {
        engine = eng;
    }

    HarpyCG emit(Instruction inst)
    {
        program ~= inst;
        return this;
    }

    HarpyCG label(string name)
    {
        if (name in labels)
            throw new Exception("Label already exists: " ~ name);
        labels[name] = cast(int) program.length;
        return this;
    }

    HarpyCG push(Value v)
    {
        emit(Instruction(OpCode.PUSH, v));
        return this;
    }

    HarpyCG pop()
    {
        emit(Instruction(OpCode.POP));
        return this;
    }

    HarpyCG storeLocal(string name)
    {
        emit(Instruction(OpCode.STOREL, engine.makeStr(name)));
        return this;
    }

    HarpyCG loadLocal(string name)
    {
        emit(Instruction(OpCode.LOADL, engine.makeStr(name)));
        return this;
    }

    HarpyCG callLabel(string name)
    {
        auto placeholder = engine.makeInt(-1);
        emit(Instruction(OpCode.CALL, placeholder));
        callPatchIndices ~= cast(int) program.length - 1;
        callPatchNames ~= name;
        return this;
    }

    Instruction[] build()
    {
        // patch calls
        foreach (i, lbl; callPatchNames)
        {
            if (!(lbl in labels))
                throw new Exception("Referencia indefinida para a label: " ~ lbl);
            int targetAddr = labels[lbl];
            int patchIdx = callPatchIndices[i];
            EValue ev;
            ev.i64 = cast(long) targetAddr;
            Value v;
            v.type = Type.Int;
            v.value = ev;
            program[patchIdx].val = v;
        }
        return program;
    }
}

class HarpyDisassembler
{
    static string valueToString(Value v)
    {
        final switch (v.type)
        {
        case Type.Int:
            return to!string(v.value.i64);
        case Type.Float:
            return format("%.8f", v.value.f64);
        case Type.String:
            return "\"" ~ v.value.str ~ "\"";
        case Type.Bool:
            return v.value.i1 ? "verdadeiro" : "falso";
        case Type.Array:
            return format("<Array[%d]>", v.value.array.length);
        case Type.Struct:
            return format("<Struct[%d]>", v.value.struct_.length);
        case Type.Enum:
            return format("<Enum[%d]>", v.value.enum_.length);
        }
    }

    static void run(Instruction[] code)
    {
        writeln("=== Harpy Disassembler ===\n");
        for (ulong pc = 0; pc < code.length; pc++)
        {
            Instruction inst = code[pc];
            writef("%04d: ", pc);
            switch (inst.op)
            {
            case OpCode.PUSH:
                writefln("PUSH %s", valueToString(inst.val));
                break;
            case OpCode.POP:
                writeln("POP");
                break;
            case OpCode.DUP:
                writeln("DUP");
                break;
            case OpCode.ADDI:
                writeln("ADDI");
                break;
            case OpCode.SUBI:
                writeln("SUBI");
                break;
            case OpCode.MULI:
                writeln("MULI");
                break;
            case OpCode.DIVI:
                writeln("DIVI");
                break;
            case OpCode.MODI:
                writeln("MODI");
                break;
            case OpCode.ADD:
                writeln("ADD");
                break;
            case OpCode.SUB:
                writeln("SUB");
                break;
            case OpCode.MUL:
                writeln("MUL");
                break;
            case OpCode.DIV:
                writeln("DIV");
                break;
            case OpCode.MOD:
                writeln("MOD");
                break;
            case OpCode.ADDF:
                writeln("ADDF");
                break;
            case OpCode.SUBF:
                writeln("SUBF");
                break;
            case OpCode.MULF:
                writeln("MULF");
                break;
            case OpCode.DIVF:
                writeln("DIVF");
                break;
            case OpCode.MODF:
                writeln("MODF");
                break;
            case OpCode.AND:
                writeln("AND");
                break;
            case OpCode.OR:
                writeln("OR");
                break;
            case OpCode.XOR:
                writeln("XOR");
                break;
            case OpCode.NOT:
                writeln("NOT");
                break;
            case OpCode.SHR:
                writeln("SHR");
                break;
            case OpCode.SHL:
                writeln("SHL");
                break;
            case OpCode.SAR:
                writeln("SAR");
                break;
            case OpCode.LOADL:
                writefln("LOADL %s", valueToString(inst.val));
                break;
            case OpCode.STOREL:
                writefln("STOREL %s", valueToString(inst.val));
                break;
            case OpCode.LOADG:
                writefln("LOADG %s", valueToString(inst.val));
                break;
            case OpCode.STOREG:
                writefln("STOREG %s", valueToString(inst.val));
                break;
            case OpCode.JMP:
                writefln("JMP %d", inst.val.value.i64);
                break;
            case OpCode.JZ:
                writefln("JZ %d", inst.val.value.i64);
                break;
            case OpCode.JNZ:
                writefln("JNZ %d", inst.val.value.i64);
                break;
            case OpCode.LT:
                writeln("LT");
                break;
            case OpCode.LE:
                writeln("LE");
                break;
            case OpCode.GT:
                writeln("GT");
                break;
            case OpCode.GTE:
                writeln("GTE");
                break;
            case OpCode.EQ:
                writeln("EQ");
                break;
            case OpCode.NE:
                writeln("NE");
                break;
            case OpCode.ARRN:
                writeln("ARRN");
                break;
            case OpCode.ARRG:
                writeln("ARRG");
                break;
            case OpCode.ARRS:
                writeln("ARRS");
                break;
            case OpCode.ARRL:
                writeln("ARRL");
                break;
            case OpCode.STRUCTN:
                writefln("STRUCTN %d", inst.val.value.i64);
                break;
            case OpCode.STRUCTS:
                writefln("STRUCTS %d", inst.val.value.i64);
                break;
            case OpCode.STRUCTG:
                writefln("STRUCTG %d", inst.val.value.i64);
                break;
            case OpCode.CALL:
                writefln("CALL %d", inst.val.value.i64);
                break;
            case OpCode.RET:
                writeln("RET");
                break;
            case OpCode.FFIL:
                writefln("FFIL %s", valueToString(inst.val));
                break;
            case OpCode.FFILI:
                writeln("FFILI");
                break;
            case OpCode.FFIC:
                writeln("FFIC");
                break;
            case OpCode.PRINT:
                writeln("PRINT");
                break;
            case OpCode.HALT:
                writeln("HALT");
                break;
            default:
                writefln("OPCODE DESCONHECIDO: %s", inst.op);
                break;
            }
        }
        writeln("\n=== Fim ===");
    }
}

// void main()
// {
//     HarpyVM motor = new HarpyVM;

//     // cria uma struct com field nome e idade
//     // estrutura Usuario { nome texto, idade inteiro }
//     // cria uma variavel inicializando os campos e tudo mais, então nesse exemplo é como se fosse
//     // alocar u Usuario = Usuario("Fernando", 69)
//     // e depois
//     // u.idade = 17
//     // print(u.nome, " ")
//     // print(u.idade, "\n")
//     // Instruction[] code = [
//     //     Instruction(OpCode.PUSH, motor.makeInt(69)),
//     //     Instruction(OpCode.PUSH, motor.makeStr("Fernando")),
//     //     Instruction(OpCode.STRUCTN, motor.makeInt(2)),
//     //     Instruction(OpCode.STOREL, motor.makeStr("u")),

//     //     // altera a idade
//     //     Instruction(OpCode.LOADL, motor.makeStr("u")),
//     //     Instruction(OpCode.PUSH, motor.makeInt(17)),
//     //     Instruction(OpCode.STRUCTS, motor.makeInt(1)),

//     //     // mostra o nome
//     //     Instruction(OpCode.LOADL, motor.makeStr("u")),
//     //     Instruction(OpCode.STRUCTG, motor.makeInt(0)),
//     //     Instruction(OpCode.PRINT),

//     //     Instruction(OpCode.PUSH, motor.makeStr(" ")),
//     //     Instruction(OpCode.PRINT),

//     //     // mostra a idade
//     //     Instruction(OpCode.LOADL, motor.makeStr("u")),
//     //     Instruction(OpCode.STRUCTG, motor.makeInt(1)),
//     //     Instruction(OpCode.PRINT),

//     //     Instruction(OpCode.PUSH, motor.makeStr("\n")),
//     //     Instruction(OpCode.PRINT),

//     //     // fim
//     //     Instruction(OpCode.HALT)
//     // ];
//     // Principal
//     Instruction[] code = [
//         Instruction(OpCode.JMP, motor.makeInt(10)), // pula para principal

//         // Função modificar (endereço 1-8)
//         // duplica antes de salvar
//         Instruction(OpCode.STOREL, motor.makeStr("u")), // salva parâmetro u
//         Instruction(OpCode.LOADL, motor.makeStr("u")), // carrega u
//         Instruction(OpCode.DUP),
//         Instruction(OpCode.STOREL, motor.makeStr("copia")), // copia = u (MESMA REFERÊNCIA!)
//         Instruction(OpCode.LOADL, motor.makeStr("copia")), // carrega copia
//         Instruction(OpCode.PUSH, motor.makeInt(99)),
//         Instruction(OpCode.STRUCTS, motor.makeInt(1)), // copia.idade = 99
//         Instruction(OpCode.POP),
//         Instruction(OpCode.RET),

//         // Principal (endereço 9+)
//         Instruction(OpCode.PUSH, motor.makeInt(17)),
//         Instruction(OpCode.PUSH, motor.makeStr("Fernando")),
//         Instruction(OpCode.STRUCTN, motor.makeInt(2)),
//         Instruction(OpCode.STOREL, motor.makeStr("u")),

//         // Imprime idade ANTES da chamada
//         Instruction(OpCode.LOADL, motor.makeStr("u")),
//         Instruction(OpCode.STRUCTG, motor.makeInt(1)),
//         Instruction(OpCode.PRINT),
//         Instruction(OpCode.PUSH, motor.makeStr(" -> ")),
//         Instruction(OpCode.PRINT),

//         // Chama modificar(u)
//         Instruction(OpCode.LOADL, motor.makeStr("u")),
//         Instruction(OpCode.CALL, motor.makeInt(1)),

//         // Imprime idade DEPOIS da chamada
//         Instruction(OpCode.LOADL, motor.makeStr("u")),
//         Instruction(OpCode.STRUCTG, motor.makeInt(1)),
//         Instruction(OpCode.PRINT),
//         Instruction(OpCode.PUSH, motor.makeStr("\n")),
//         Instruction(OpCode.PRINT),

//         Instruction(OpCode.HALT)
//     ];

//     motor.code = code;
//     motor.run();

// }
