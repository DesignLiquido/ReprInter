module middle.harpy_optimizer;

import std.stdio, std.conv, std.format, std.algorithm;
import backend.harpyvm : OpCode, EValue, Value, Type, Instruction;
import erro;

// Sistema de otimização multi-passe da HarpyVM
// Implementa: constant folding, constant propagation, algebraic simplification,
// strength reduction, dead store elimination, peephole optimization
class HarpyOptimizer
{
private:
    public Instruction[] instructions;
    Value[string] globalConsts;
    Value[string] localConsts;
    Value[string] copyMap;
    long[long] addressMap;

    static bool isFoldable(OpCode op) pure nothrow @nogc @safe
    {
        switch (op)
        {
        case OpCode.ADDI, OpCode.SUBI, OpCode.MULI, OpCode.DIVI,
            OpCode.ADDF, OpCode.SUBF, OpCode.MULF, OpCode.DIVF,
            OpCode.MODF, OpCode.MODI, OpCode.NOT, OpCode.XOR, OpCode.AND, OpCode.SHR, OpCode.SHL, OpCode.SAR, OpCode
                .OR:
                return true;
        default:
            return false;
        }
    }

    static bool isComparison(OpCode op) pure nothrow @nogc @safe
    {
        switch (op)
        {
        case OpCode.EQ, OpCode.NE, OpCode.LT, OpCode.LE, OpCode.GT, OpCode.GE:
            return true;
        default:
            return false;
        }
    }

    // Constant folding inline para operações aritméticas
    pragma(inline, true)
    bool foldArithmetic(ref Instruction[] output, OpCode op, ref Value v1, ref Value v2)
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
                return false;
            result.i64 = v1.value.i64 / v2.value.i64;
            resultType = Type.Int;
            break;
        case OpCode.MODI:
            if (v2.value.i64 == 0)
                return false;
            result.i64 = v1.value.i64 % v2.value.i64;
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
                return false;
            result.f64 = v1.value.f64 / v2.value.f64;
            resultType = Type.Float;
            break;
        case OpCode.MODF:
            if (v2.value.f64 == 0.0)
                return false;
            result.f64 = v1.value.f64 % v2.value.f64;
            resultType = Type.Float;
            break;
            // OpCode.XOR, OpCode.AND, OpCode.SHR, OpCode.SHL, OpCode.SAR, OpCode.OR
        case OpCode.NOT:
            result.i64 = ~v1.value.i64;
            resultType = Type.Int;
            break;
        case OpCode.XOR:
            result.i64 = v1.value.i64 ^ v2.value.i64;
            resultType = Type.Int;
            break;
        case OpCode.AND:
            result.i64 = v1.value.i64 & v2.value.i64;
            resultType = Type.Int;
            break;
        case OpCode.OR:
            result.i64 = v1.value.i64 | v2.value.i64;
            resultType = Type.Int;
            break;
        case OpCode.SHR:
            result.i64 = v1.value.i64 >> v2.value.i64;
            resultType = Type.Int;
            break;
        case OpCode.SAR:
            result.i64 = v1.value.i64 >>> v2.value.i64;
            resultType = Type.Int;
            break;
        case OpCode.SHL:
            result.i64 = v1.value.i64 << v2.value.i64;
            resultType = Type.Int;
            break;
        default:
            return false;
        }
        output ~= Instruction(OpCode.PUSH, Value(resultType, result));
        return true;
    }

    // Constant folding para comparações
    pragma(inline, true)
    bool foldComparison(ref Instruction[] output, OpCode op, ref Value v1, ref Value v2)
    {
        EValue result;
        if (v1.type == Type.Int && v2.type == Type.Int)
        {
            switch (op)
            {
            case OpCode.EQ:
                result.i1 = (v1.value.i64 == v2.value.i64) ? 1 : 0;
                break;
            case OpCode.NE:
                result.i1 = (v1.value.i64 != v2.value.i64) ? 1 : 0;
                break;
            case OpCode.LT:
                result.i1 = (v1.value.i64 < v2.value.i64) ? 1 : 0;
                break;
            case OpCode.LE:
                result.i1 = (v1.value.i64 <= v2.value.i64) ? 1 : 0;
                break;
            case OpCode.GT:
                result.i1 = (v1.value.i64 > v2.value.i64) ? 1 : 0;
                break;
            case OpCode.GE:
                result.i1 = (v1.value.i64 >= v2.value.i64) ? 1 : 0;
                break;
            default:
                return false;
            }
        }
        else if (v1.type == Type.Float && v2.type == Type.Float)
        {
            switch (op)
            {
            case OpCode.EQ:
                result.i1 = (v1.value.f64 == v2.value.f64) ? 1 : 0;
                break;
            case OpCode.NE:
                result.i1 = (v1.value.f64 != v2.value.f64) ? 1 : 0;
                break;
            case OpCode.LT:
                result.i1 = (v1.value.f64 < v2.value.f64) ? 1 : 0;
                break;
            case OpCode.LE:
                result.i1 = (v1.value.f64 <= v2.value.f64) ? 1 : 0;
                break;
            case OpCode.GT:
                result.i1 = (v1.value.f64 > v2.value.f64) ? 1 : 0;
                break;
            case OpCode.GE:
                result.i1 = (v1.value.f64 >= v2.value.f64) ? 1 : 0;
                break;
            default:
                return false;
            }
        }
        else
            return false;
        output ~= Instruction(OpCode.PUSH, Value(Type.Bool, result));
        return true;
    }

    // Peephole: simplificações algébricas (x + 0, x * 1, x * 0, etc)
    bool algebraicSimplification(ref Instruction[] output, ref Instruction inst, long i)
    {
        // x + 0 = x ou x - 0 = x
        if ((inst.op == OpCode.ADDI || inst.op == OpCode.SUBI ||
                inst.op == OpCode.ADDF || inst.op == OpCode.SUBF) &&
            output.length > 0 && output[$ - 1].op == OpCode.PUSH)
        {
            auto lastVal = output[$ - 1].val;
            bool isZero = (lastVal.type == Type.Int && lastVal.value.i64 == 0) ||
                (lastVal.type == Type.Float && lastVal.value.f64 == 0.0);

            if (isZero)
            {
                output = output[0 .. $ - 1]; // Remove PUSH 0 e operação
                return true;
            }
        }

        // x * 1 = x
        if ((inst.op == OpCode.MULI || inst.op == OpCode.MULF) &&
            output.length > 0 && output[$ - 1].op == OpCode.PUSH)
        {
            auto lastVal = output[$ - 1].val;
            bool isOne = (lastVal.type == Type.Int && lastVal.value.i64 == 1) ||
                (lastVal.type == Type.Float && lastVal.value.f64 == 1.0);

            if (isOne)
            {
                output = output[0 .. $ - 1]; // Remove PUSH 1 e multiplicação
                return true;
            }
        }

        // x * 0 = 0
        if ((inst.op == OpCode.MULI || inst.op == OpCode.MULF) &&
            output.length > 1 && output[$ - 1].op == OpCode.PUSH)
        {
            auto lastVal = output[$ - 1].val;
            bool isZero = (lastVal.type == Type.Int && lastVal.value.i64 == 0) ||
                (lastVal.type == Type.Float && lastVal.value.f64 == 0.0);

            if (isZero && output[$ - 2].op == OpCode.PUSH)
            {
                // Remove os dois PUSHs anteriores e deixa só PUSH 0
                output = output[0 .. $ - 2];
                output ~= Instruction(OpCode.PUSH, lastVal);
                return true;
            }
        }

        // x / 1 = x
        if ((inst.op == OpCode.DIVI || inst.op == OpCode.DIVF) &&
            output.length > 0 && output[$ - 1].op == OpCode.PUSH)
        {
            auto lastVal = output[$ - 1].val;
            bool isOne = (lastVal.type == Type.Int && lastVal.value.i64 == 1) ||
                (lastVal.type == Type.Float && lastVal.value.f64 == 1.0);

            if (isOne)
            {
                output = output[0 .. $ - 1];
                return true;
            }
        }

        return false;
    }

    // Strength reduction: x * 2 → x + x
    bool strengthReduction(ref Instruction[] output, ref Instruction inst)
    {
        if (inst.op == OpCode.MULI && output.length > 0 &&
            output[$ - 1].op == OpCode.PUSH &&
            output[$ - 1].val.type == Type.Int)
        {
            long val = output[$ - 1].val.value.i64;

            // x * 2 → DUP + ADD (mais rápido)
            if (val == 2)
            {
                output = output[0 .. $ - 1]; // Remove PUSH 2
                output ~= Instruction(OpCode.DUP);
                output ~= Instruction(OpCode.ADDI);
                return true;
            }
        }

        return false;
    }

    // Dead store elimination: detecta stores sem uso subsequente
    bool deadStoreElimination(ref long i, long len)
    {
        auto inst = instructions[i];

        if (inst.op != OpCode.STOREL && inst.op != OpCode.STOREG)
            return false;

        string varName = inst.val.value.str;
        bool temLoad = false;

        // Procura em uma janela de 200 instruções
        for (long j = i + 1; j < len && j < i + 200; j++)
        {
            auto futInst = instructions[j];

            // Se encontrar LOAD dessa variável, ela é usada
            if ((futInst.op == OpCode.LOADL || futInst.op == OpCode.LOADG) &&
                futInst.val.value.str == varName)
            {
                temLoad = true;
                break;
            }

            // Se encontrar outro STORE na mesma variável antes de qualquer LOAD
            if ((futInst.op == OpCode.STOREL || futInst.op == OpCode.STOREG) &&
                futInst.val.value.str == varName)
                return !temLoad;

            // Se encontrar CALL, pode invalidar análise (efeitos colaterais)
            if (futInst.op == OpCode.CALL || futInst.op == OpCode.FFIC ||
                futInst.op == OpCode.FFIL)
                break;
        }

        return false;
    }

    // Corrige endereços de JMP, CALL após otimização
    void fixAddresses(ref Instruction[] output)
    {
        foreach (ref inst; output)
        {
            if (inst.op == OpCode.JMP || inst.op == OpCode.JZ ||
                inst.op == OpCode.JNZ)
            {
                long oldAddr = cast(long) inst.val.value.i64;
                if (oldAddr in addressMap)
                    inst.val.value.i64 = cast(long) addressMap[oldAddr];
            }
            else if (inst.op == OpCode.CALL)
            {
                long oldAddr = cast(long) inst.val.value.i64;
                if (oldAddr in addressMap)
                    inst.val.value.i64 = cast(long) addressMap[oldAddr];
            }
        }
    }

public:
    this(ref Instruction[] instructions)
    {
        this.instructions = instructions;
    }

    Instruction[] optimize()
    {
        Instruction[] output;
        output.reserve(instructions.length);

        long i = 0;
        long len = instructions.length;

        while (i < len)
        {
            // Mapeia endereço antigo → novo
            addressMap[i] = output.length;

            // 1. Constant folding (aritmética)
            if (i + 2 < len)
            {
                auto i0 = instructions[i];
                auto i1 = instructions[i + 1];
                auto i2 = instructions[i + 2];

                if (i0.op == OpCode.PUSH && i1.op == OpCode.PUSH)
                {
                    // Tenta fold aritmético
                    if (isFoldable(i2.op))
                    {
                        long before = output.length;
                        if (foldArithmetic(output, i2.op, i0.val, i1.val))
                        {
                            addressMap[i + 1] = output.length;
                            addressMap[i + 2] = output.length;
                            i += 3;
                            continue;
                        }
                    }

                    // Tenta fold de comparação
                    if (isComparison(i2.op))
                    {
                        if (foldComparison(output, i2.op, i0.val, i1.val))
                        {
                            addressMap[i + 1] = output.length;
                            addressMap[i + 2] = output.length;
                            i += 3;
                            continue;
                        }
                    }
                }
            }

            auto inst = instructions[i];

            // 2. Algebraic simplification (antes de adicionar instrução)
            if (algebraicSimplification(output, inst, i))
            {
                i++;
                continue;
            }

            // 3. Dead store elimination
            if (deadStoreElimination(i, len))
            {
                i++;
                continue;
            }

            // 4. Constant propagation (LOADG)
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

            // 5. Constant propagation (LOADL)
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

            // 6. Tracking de STOREG
            else if (inst.op == OpCode.STOREG)
            {
                if (output.length > 0 && output[$ - 1].op == OpCode.PUSH)
                    globalConsts[inst.val.value.str] = output[$ - 1].val;
                else
                    globalConsts.remove(inst.val.value.str);
            }

            // 7. Tracking de STOREL
            else if (inst.op == OpCode.STOREL)
            {
                if (output.length > 0 && output[$ - 1].op == OpCode.PUSH)
                    localConsts[inst.val.value.str] = output[$ - 1].val;
                else
                    localConsts.remove(inst.val.value.str);
            }

            // 8. Invalida tracking em CALL/FFI
            else if (inst.op == OpCode.CALL || inst.op == OpCode.FFIC ||
                inst.op == OpCode.FFIL)
            {
                if (globalConsts.length > 0)
                    globalConsts.clear();
                if (localConsts.length > 0)
                    localConsts.clear();
            }

            output ~= inst;
            i++;
        }

        // 9. Fix de endereços após todas otimizações
        fixAddresses(output);

        instructions = output;
        return output;
    }
}
