module backend.harpyvm;
import std.stdio, std.variant, std.conv, std.datetime.stopwatch, std.string;
import core.stdc.stdio, core.stdc.stdlib, core.sys.posix.dlfcn;

enum OpCode : ubyte
{
    // Builtin
    PRINT,

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
    LTE,
    GT,
    GTE,
    EQ,
    NE,

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

    // FFI
    FFIL, // FFI Load
    FFILI, // FFI Load Inteligente
    FFIC, // FFI Call

    // Core
    PUSH,
    POP,
    CALL,
    DUP,
    // TAILCALL,
    RET,
    HALT
}

enum Type
{
    String,
    Int,
    Float,
    Bool,
    Array
}

// para ffi {{
union CValueFFI
{
    char* str; //     string
    long i64; //      int
    double f64; //    float
    bool i1; //       bool
    Value* array; //  array
}

struct ValueC
{
    Type type;
    CValueFFI value;
}
// }}

union EValue
{
    string str; //    string
    long i64; //      int
    double f64; //    float
    bool i1; //       bool
    Value[] array; // array
}

struct Value
{
    Type type;
    EValue value;
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

alias ffi_extern_function = ValueC function(ValueC*, ulong);

class HarpyVM
{
    Value[] valueStack; // global stack for temp values
    StackFrame[] frameStack;
    Value[string] heap;
    Instruction[] code;
    long pc; // program counter
    void*[string] libs;
    ffi_extern_function[string] externalFunctions;

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
        return Value(Type.Array, ev);
    }

    void run()
    {
        pc = 0;
        while (pc < code.length)
        {
            Instruction inst = code[pc];
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
                push(peek());
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
                push(currentFrame().stack[name]);
                pc++;
                break;

            case OpCode.STOREL:
                string name = inst.val.value.str;
                currentFrame().stack[name] = pop();
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
                long b = pop().value.i64;
                long a = pop().value.i64;
                push(makeInt(a < b ? 1 : 0));
                pc++;
                break;

            case OpCode.LTE:
                long b = pop().value.i64;
                long a = pop().value.i64;
                push(makeInt(a <= b ? 1 : 0));
                pc++;
                break;

            case OpCode.GT:
                long b = pop().value.i64;
                long a = pop().value.i64;
                push(makeInt(a > b ? 1 : 0));
                pc++;
                break;

            case OpCode.GTE:
                long b = pop().value.i64;
                long a = pop().value.i64;
                push(makeInt(a >= b ? 1 : 0));
                pc++;
                break;

            case OpCode.EQ:
                long b = pop().value.i64;
                long a = pop().value.i64;
                push(makeInt(a == b ? 1 : 0));
                pc++;
                break;

            case OpCode.ARRN: // array new
                long size = pop().value.i64;
                Value[] arr = new Value[size];
                for (long i = size - 1; i >= 0; i--)
                    arr[i] = pop();
                push(this.makeArray(arr));
                pc++;
                break;

            case OpCode.ARRG: // array get (idx)
                long idx = pop().value.i64;
                Value[] arr = pop().value.array;
                push(arr[idx]);
                pc++;
                break;

            case OpCode.ARRS: // array set -> arr[idx] = n
                Value val = pop();
                long idx = pop().value.i64;
                Value[] arr = pop().value.array;
                arr[idx] = val;
                push(this.makeArray(arr));
                pc++;
                break;

            case OpCode.ARRL: // array length
                Value[] arr = pop().value.array;
                push(this.makeInt(arr.length));
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

            case OpCode.FFIL: // FFI Load
                string libpath = pop().value.str;
                string libname = inst.val.value.str;
                if (libpath !in libs)
                {
                    void* handle = dlopen(libpath.toStringz, RTLD_LAZY);
                    if (!handle)
                        throw new Exception("Failed to load library: " ~ libpath);
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

                void* handle = libs[libname];
                if (!handle)
                    throw new Exception("Library not loaded: " ~ libname);

                ffi_extern_function funcPtr;
                if (funcname !in externalFunctions)
                    funcPtr = cast(ffi_extern_function) dlsym(handle, funcname.toStringz);
                else
                    funcPtr = externalFunctions[funcname];

                if (!funcPtr)
                    throw new Exception("Symbol not found: " ~ funcname);

                // Converter argumentos para C
                ValueC* args = cast(ValueC*) malloc(argc * ValueC.sizeof);
                for (long i; i < argc; i++)
                {
                    Value v = pop();
                    CValueFFI cffi;

                    final switch (v.type)
                    {
                    case Type.Bool:
                        cffi.i1 = v.value.i1;
                        break;
                    case Type.Int:
                        cffi.i64 = v.value.i64;
                        break;
                    case Type.Float:
                        cffi.f64 = v.value.f64;
                        break;
                    case Type.String:
                        cffi.str = cast(char*) v.value.str.toStringz();
                        break;
                    case Type.Array:
                        cffi.array = cast(Value*) v.value.array.ptr;
                        cffi.i64 = v.value.array.length; // tamanho do array
                        break;
                    }

                    args[i].type = v.type;
                    args[i].value = *cast(CValueFFI*)&cffi;
                }

                // Chamar função
                ValueC result = funcPtr(args, argc);

                // Converter resultado de volta
                Value vmResult;
                vmResult.type = result.type;

                final switch (result.type)
                {
                case Type.Bool:
                    vmResult.value.i1 = result.value.i1;
                    break;
                case Type.Int:
                    vmResult.value.i64 = result.value.i64;
                    break;
                case Type.Float:
                    vmResult.value.f64 = result.value.f64;
                    break;
                case Type.String:
                    vmResult.value.str = result.value.str.fromStringz.to!string;
                    break;
                case Type.Array:
                    // Reconstruir array D
                    // Precisaria saber o tamanho, assumindo que está em result.value.i64 ou similar
                    vmResult.value.array = [];
                    break;
                }

                free(args);
                push(vmResult);
                pc++;
                break;

            case OpCode.PRINT:
                Value v = pop();
                final switch (v.type)
                {
                case Type.Int:
                    printf("%lld".toStringz(), v.value.i64);
                    break;
                case Type.Float:
                    printf("%.8f".toStringz(), v.value.f64);
                    break;
                case Type.String:
                    printf("%s", v.value.str.toStringz());
                    break;
                case Type.Bool:
                    printf("%s".toStringz(), v.value.i1 ? "verdadeiro".toStringz() : "falso".toStringz());
                    break;
                case Type.Array:
                    printf("<Array>".toStringz());
                    break;
                }
                pc++;
                break;

            case OpCode.HALT:
                return;
            default:
                throw new Exception(
                    "Harpy Virtual Machine Error - OpCode inválido: " ~ to!string(inst.op));
            }
        }
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
