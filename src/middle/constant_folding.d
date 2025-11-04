module middle.constant_folding;

import std.stdio, std.conv, std.format;
import backend.harpyvm : OpCode, EValue, Value, Type, Instruction;
import erro;

// AVISO: está extremamente instavel, é necessario recriar todo o sistema
// passe de otimização -> constant folding
// esse sistema faz constant folding no bytecode da vm, nas instruções diretamente
class HarpyConstantFolding
{
private:
    Instruction[] instructions;
    Value[string] globalConsts;
    Value[string] localConsts;

    static bool isFoldable(OpCode op) pure nothrow @nogc @safe
    {
        switch (op)
        {
        case OpCode.ADDI, OpCode.SUBI, OpCode.MULI, OpCode.DIVI,
            OpCode.ADDF, OpCode.SUBF, OpCode.MULF, OpCode.DIVF, OpCode.MODF, OpCode.MODI:
            return true;
        default:
            return false;
        }
    }

    // Calcula operação inline sem criar struct temporário
    pragma(inline, true)
    void foldInline(ref Instruction[] output, OpCode op, ref Value v1, ref Value v2)
    {
        EValue result;
        Type resultType;

        switch (op)
        {
        case OpCode.ADDI:
            result.i64 = v1.value.i64 + v2.value.i64;
            resultType = Type.Int;
            break;
        case OpCode.SUBI:
            result.i64 = v1.value.i64 - v2.value.i64;
            resultType = Type.Int;
            break;
        case OpCode.MULI:
            result.i64 = v1.value.i64 * v2.value.i64;
            resultType = Type.Int;
            break;
        case OpCode.DIVI:
            if (v2.value.i64 == 0)
                return; // mantém original
            result.i64 = v1.value.i64 / v2.value.i64;
            resultType = Type.Int;
            break;
        case OpCode.ADDF:
            result.f64 = v1.value.f64 + v2.value.f64;
            resultType = Type.Float;
            break;
        case OpCode.SUBF:
            result.f64 = v1.value.f64 - v2.value.f64;
            resultType = Type.Float;
            break;
        case OpCode.MULF:
            result.f64 = v1.value.f64 * v2.value.f64;
            resultType = Type.Float;
            break;
        case OpCode.DIVF:
            if (v2.value.f64 == 0.0)
                return; // mantém original
            result.f64 = v1.value.f64 / v2.value.f64;
            resultType = Type.Float;
            break;
        case OpCode.MODF:
            if (v2.value.f64 == 0.0)
                return; // mantém original
            result.f64 = v1.value.f64 / v2.value.f64;
            resultType = Type.Float;
            break;
        case OpCode.MODI:
            if (v2.value.i64 == 0)
                return; // mantém original
            result.i64 = v1.value.i64 / v2.value.i64;
            resultType = Type.Int;
            break;
        default:
            return;
        }
        output ~= Instruction(OpCode.PUSH, Value(resultType, result));
    }

public:
    this(ref Instruction[] instructions)
    {
        this.instructions = instructions;
    }

    Instruction[] opt()
    {
        // Pre-aloca com tamanho exato (vai ser ≤ tamanho original)
        Instruction[] output;
        output.reserve(instructions.length);

        size_t i = 0;
        size_t len = instructions.length;

        while (i < len)
        {
            // Fast path: tenta constant folding (padrão mais comum)
            if (i + 2 < len)
            {
                auto i0 = instructions[i];
                auto i1 = instructions[i + 1];
                auto i2 = instructions[i + 2];

                if (i0.op == OpCode.PUSH &&
                    i1.op == OpCode.PUSH &&
                    isFoldable(i2.op))
                {
                    size_t before = output.length;
                    foldInline(output, i2.op, i0.val, i1.val);

                    if (output.length > before) // fold bem-sucedido
                    {
                        i += 3;
                        continue;
                    }
                    // Se não deu fold (div by zero), copia as 3 instruções
                    output ~= i0;
                    output ~= i1;
                    output ~= i2;
                    i += 3;
                    continue;
                }
            }

            auto inst = instructions[i];
            // Propagação de LOADG
            if (inst.op == OpCode.LOADG)
            {
                auto ptr = inst.val.value.str in globalConsts;
                if (ptr)
                {
                    output ~= Instruction(OpCode.PUSH, *ptr);
                    i++;
                    continue;
                }
            }
            // Propagação de LOADL
            else if (inst.op == OpCode.LOADL)
            {
                auto ptr = inst.val.value.str in localConsts;
                if (ptr)
                {
                    output ~= Instruction(OpCode.PUSH, *ptr);
                    i++;
                    continue;
                }
            }
            // Tracking de STOREG
            else if (inst.op == OpCode.STOREG)
                if (output.length > 0 && output[$ - 1].op == OpCode.PUSH)
                    globalConsts[inst.val.value.str] = output[$ - 1].val;
                else
                    globalConsts.remove(inst.val.value.str);
            // Tracking de STOREL
            else if (inst.op == OpCode.STOREL)
                if (output.length > 0 && output[$ - 1].op == OpCode.PUSH)
                    localConsts[inst.val.value.str] = output[$ - 1].val;
                else
                    localConsts.remove(inst.val.value.str);
            // Invalida tracking em CALL/FFI
            else if (inst.op == OpCode.CALL || inst.op == OpCode.FFIC || inst.op == OpCode.FFIL)
            {
                if (globalConsts.length > 0)
                    globalConsts.clear();
                if (localConsts.length > 0)
                    localConsts.clear();
            }
            output ~= inst;
            i++;
        }

        instructions = output;
        return output;
    }
}
