module vm;
import core.stdc.stdio, core.stdc.stdlib, core.stdc.string;

const MAX_STACK = 1024;
const MAX_CONSTANTS = 256;
const MAX_PROGRAM = 2048;

// Tipos de valores
enum ValueType : ubyte
{
    Int,
    Float,
    Double,
    Bool,
    None
}

// Union para valores
union Value
{
    int i32;
    float f32;
    double f64;
    bool i1;
}

// OpCodes da VM
enum OpCode : ubyte
{
    // Stack operations
    Push, // Push constante pelo índice
    Pop, // Remove topo da stack
    Dup, // Duplica topo

    // Arithmetic
    AddI32,
    SubI32,
    MulI32,
    DivI32,
    ModI32,
    NegI32, // Negação

    // Comparisons (colocam bool na stack)
    EqI32, // ==
    NeI32, // !=
    LtI32, // <
    GtI32, // >
    LeI32, // <=
    GeI32, // >=

    // Logical
    And,
    Or,
    Not,

    // I/O
    Print,
    PrintLn,

    // Control flow
    Jump, // Jump incondicional
    JumpIfTrue,
    JumpIfFalse,

    Halt,
    Nop, // No operation
}

// Instrução (opcode + operando opcional)
struct Instruction
{
    OpCode op;
    int operand = 0; // Para Push (índice), Jumps (offset), etc
}

// Valor tipado
struct TypedValue
{
    ValueType type;
    Value value;

    // Helpers para criar valores
    static TypedValue makeInt(int val)
    {
        TypedValue tv;
        tv.type = ValueType.Int;
        tv.value.i32 = val;
        return tv;
    }

    static TypedValue makeBool(bool val)
    {
        TypedValue tv;
        tv.type = ValueType.Bool;
        tv.value.i1 = val;
        return tv;
    }

    static TypedValue makeFloat(float val)
    {
        TypedValue tv;
        tv.type = ValueType.Float;
        tv.value.f32 = val;
        return tv;
    }
}

struct VM
{
    // Programa
    protected Instruction[MAX_PROGRAM] program;
    protected size_t programSize = 0;
    protected size_t pc = 0; // Program Counter

    // Stack de execução
    protected TypedValue[MAX_STACK] stack;
    protected size_t sp = 0; // Stack Pointer

    // Pool de constantes
    protected TypedValue[MAX_CONSTANTS] constants;
    protected size_t constantCount = 0;

    // Status
    protected bool halted = false;

    // Adiciona constante ao pool e retorna índice
    int addConstant(TypedValue val)
    {
        if (constantCount >= MAX_CONSTANTS)
        {
            printf("Erro: Pool de constantes cheio!\n");
            exit(1);
        }
        constants[constantCount] = val;
        return cast(int)(constantCount++);
    }

    // Adiciona instrução ao programa
    void emit(OpCode op, int operand = 0)
    {
        if (programSize >= MAX_PROGRAM)
        {
            printf("Erro: Programa muito grande!\n");
            exit(1);
        }
        program[programSize].op = op;
        program[programSize].operand = operand;
        programSize++;
    }

    void run()
    {
        halted = false;
        pc = 0;
        sp = 0;

        while (pc < programSize && !halted)
        {
            Instruction instr = program[pc];
            execute(instr);
            pc++;
        }
    }

    void push(TypedValue val)
    {
        if (sp >= MAX_STACK)
        {
            printf("Stack overflow!\n");
            exit(1);
        }
        stack[sp++] = val;
    }

    TypedValue pop()
    {
        if (sp == 0)
        {
            printf("Stack underflow!\n");
            exit(1);
        }
        return stack[--sp];
    }

    TypedValue peek()
    {
        if (sp == 0)
        {
            printf("Stack vazia!\n");
            exit(1);
        }
        return stack[sp - 1];
    }

    void execute(Instruction instr)
    {
        switch (instr.op)
        {
        case OpCode.Push:
            if (instr.operand < 0 || instr.operand >= constantCount)
            {
                printf("Erro: Índice de constante inválido: %d\n", instr.operand);
                exit(1);
            }
            push(constants[instr.operand]);
            break;

        case OpCode.Pop:
            pop();
            break;

        case OpCode.Dup:
            push(peek());
            break;

            // Arithmetic
        case OpCode.AddI32:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeInt(a.value.i32 + b.value.i32));
            break;

        case OpCode.SubI32:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeInt(a.value.i32 - b.value.i32));
            break;

        case OpCode.MulI32:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeInt(a.value.i32 * b.value.i32));
            break;

        case OpCode.DivI32:
            TypedValue b = pop();
            TypedValue a = pop();
            if (b.value.i32 == 0)
            {
                printf("Erro: Divisão por zero!\n");
                exit(1);
            }
            push(TypedValue.makeInt(a.value.i32 / b.value.i32));
            break;

        case OpCode.ModI32:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeInt(a.value.i32 % b.value.i32));
            break;

        case OpCode.NegI32:
            TypedValue a = pop();
            push(TypedValue.makeInt(-a.value.i32));
            break;

            // Comparisons
        case OpCode.EqI32:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeBool(a.value.i32 == b.value.i32));
            break;

        case OpCode.NeI32:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeBool(a.value.i32 != b.value.i32));
            break;

        case OpCode.LtI32:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeBool(a.value.i32 < b.value.i32));
            break;

        case OpCode.GtI32:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeBool(a.value.i32 > b.value.i32));
            break;

        case OpCode.LeI32:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeBool(a.value.i32 <= b.value.i32));
            break;

        case OpCode.GeI32:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeBool(a.value.i32 >= b.value.i32));
            break;

            // Logical
        case OpCode.And:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeBool(a.value.i1 && b.value.i1));
            break;

        case OpCode.Or:
            TypedValue b = pop();
            TypedValue a = pop();
            push(TypedValue.makeBool(a.value.i1 || b.value.i1));
            break;

        case OpCode.Not:
            TypedValue a = pop();
            push(TypedValue.makeBool(!a.value.i1));
            break;

            // I/O
        case OpCode.Print:
            if (sp > 0)
            {
                TypedValue top = peek();
                if (top.type == ValueType.Int)
                    printf("%d", top.value.i32);
                else if (top.type == ValueType.Bool)
                    printf("%s", top.value.i1 ? cast(const char*) "true" : cast(const char*) "false");
                else if (top.type == ValueType.Float)
                    printf("%f", top.value.f32);
            }
            break;

        case OpCode.PrintLn:
            if (sp > 0)
            {
                TypedValue top = pop();
                if (top.type == ValueType.Int)
                    printf("%d\n", top.value.i32);
                else if (top.type == ValueType.Bool)
                    printf("%s\n", top.value.i1 ? cast(const char*) "true" : cast(
                            const char*) "false");
                else if (top.type == ValueType.Float)
                    printf("%f\n", top.value.f32);
            }
            break;

            // Control flow
        case OpCode.Jump:
            pc = instr.operand - 1; // -1 porque pc++ acontece no loop
            break;

        case OpCode.JumpIfTrue:
            TypedValue cond = pop();
            if (cond.value.i1)
                pc = instr.operand - 1;
            break;

        case OpCode.JumpIfFalse:
            TypedValue cond = pop();
            if (!cond.value.i1)
                pc = instr.operand - 1;
            break;

        case OpCode.Halt:
            halted = true;
            break;

        case OpCode.Nop:
            break;

        default:
            printf("OpCode desconhecido: %d\n", instr.op);
            break;
        }
    }

    // Debug: imprime stack
    void dumpStack()
    {
        printf("=== Stack (SP=%zu) ===\n", sp);
        for (size_t i = 0; i < sp; i++)
        {
            printf("[%zu] ", i);
            if (stack[i].type == ValueType.Int)
                printf("int: %d\n", stack[i].value.i32);
            else if (stack[i].type == ValueType.Bool)
                printf("bool: %s\n", stack[i].value.i1 ? cast(const char*) "true" : cast(
                        const char*) "false");
        }
        printf("==================\n");
    }
}
