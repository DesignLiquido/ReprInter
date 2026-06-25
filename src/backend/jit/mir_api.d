module backend.jit.mir_api;

/**
 * mir_api.d — API de alto nível em D para a biblioteca MIR (vnmakarov/mir)
 *
 * Fornece wrappers orientados a objetos sobre os bindings C de baixo nível,
 * tornando a construção de código MIR mais idiomática e segura em D.
 *
 * Compilação:
 *   ldc2 -betterC mir_api.d mir.d /usr/local/lib/libmir.a -L-lm -L-ldl -L-lpthread
 *
 * Exemplo rápido:
 *   auto ctx  = new MirContext();
 *   auto mod  = ctx.newModule("meu_modulo");
 *   auto func = mod.newFunc("soma", [MIR_T_I64], [MIR_var("a", MIR_T_I64),
 *                                                  MIR_var("b", MIR_T_I64)]);
 *   auto ra   = func.reg("a");
 *   auto rb   = func.reg("b");
 *   auto rres = func.newReg("res", MIR_T_I64);
 *   func.add(rres, ra, rb);   // ADD res, a, b
 *   func.ret(rres);            // RET res
 *   func.finish();
 *   mod.finish();
 *   // ... link e JIT ...
 */

public import backend.jit.mir; // bindings C gerados em mir.d
import core.stdc.stdio : FILE;
import core.stdc.string : strlen;

extern (C):
// =============================================================================
// Helpers de tipo públicos
// =============================================================================

/// Atalho para construir MIR_var_t de forma legível.
/// Uso: MIR_var("x", MIR_type_t.MIR_T_I64)
MIR_var_t MIR_var(const(char)* name, MIR_type_t type, size_t size = 0) pure
{
    MIR_var_t v;
    v.name = name;
    v.type = type;
    v.size = size;
    return v;
}

// =============================================================================
// MirOp — wrapper fino sobre MIR_op_t para encadear operandos
// =============================================================================

/**
 * MirOp representa um operando MIR (registrador, imediato, memória, etc.).
 *
 * É uma estrutura de valor (sem alocação dinâmica) compatível com .
 * Toda função de construção de instrução aceita MirOp diretamente.
 */
struct MirOp
{
    MIR_op_t raw; /// Operando C subjacente.

    /// Constrói a partir de um MIR_op_t bruto (interoperabilidade).
    static MirOp fromRaw(MIR_op_t op) pure
    {
        MirOp o;
        o.raw = op;
        return o;
    }

    /// Verdadeiro se o operando representa um registrador virtual.
    bool isReg() const pure
    {
        return raw.mode == MIR_op_mode_t.MIR_OP_REG;
    }

    /// Verdadeiro se o operando é um inteiro imediato.
    bool isInt() const pure
    {
        return raw.mode == MIR_op_mode_t.MIR_OP_INT;
    }

    /// Verdadeiro se o operando é uma referência a item (função/dado).
    bool isRef() const pure
    {
        return raw.mode == MIR_op_mode_t.MIR_OP_REF;
    }
}

// =============================================================================
// MirFunc — constrói o corpo de uma função MIR
// =============================================================================

/**
 * MirFunc encapsula um MIR_item_t do tipo função e oferece métodos
 * de alto nível para emitir instruções, criar registradores e labels.
 *
 * Ciclo de vida:
 *   1. Obtido via MirModule.newFunc() ou MirModule.newVarArgFunc().
 *   2. Instruções emitidas com os métodos abaixo (mov, add, call, ret, …).
 *   3. Encerrado com finish() — NÃO chame diretamente MIR_finish_func.
 */
final class MirFunc
{
private:
    MIR_context_t _ctx;
    MIR_item_t _item;

    MIR_func_t _func()
    {
        return MIR_get_item_func(_ctx, _item);
    }

public:
    /// Construído internamente por MirModule; não instancie diretamente.
    this(MIR_context_t ctx, MIR_item_t item)
    {
        _ctx = ctx;
        _item = item;
    }

    /// Item C subjacente (para interoperabilidade com a API de baixo nível).
    MIR_item_t item()
    {
        return _item;
    }

    // -------------------------------------------------------------------------
    // Registradores
    // -------------------------------------------------------------------------

    /**
     * Cria um novo registrador virtual de nome `name` e tipo `type`.
     *
     * Assembly gerado (exemplo para MIR_T_I64):
     *   ; nenhum código emitido — apenas metadado de SSA alocado no contexto
     *
     * Uso:
     *   auto r = func.newReg("tmp", MIR_type_t.MIR_T_I64);
     */
    pragma(mangle, "MIR_new_func_reg")
    extern (C) static MIR_reg_t _mir_new_func_reg(
        MIR_context_t, void*, MIR_type_t, const(char)*);

    MirOp newReg(const(char)* name, MIR_type_t type)
    {
        auto r = MIR_new_func_reg(_ctx, _func(), type, name);
        return MirOp.fromRaw(MIR_new_reg_op(_ctx, r));
    }

    /**
     * Retorna o operando registrador para uma variável de parâmetro já
     * declarada com o nome `name`.
     *
     * Uso:
     *   auto rA = func.reg("a");   // parâmetro "a"
     */
    MirOp reg(const(char)* name)
    {
        auto r = MIR_reg(_ctx, name, _func());
        return MirOp.fromRaw(MIR_new_reg_op(_ctx, r));
    }

    // -------------------------------------------------------------------------
    // Labels
    // -------------------------------------------------------------------------

    /**
     * Cria e retorna um novo label (alvo de branch).
     *
     * Assembly gerado:
     *   L42:           ; rótulo sem instrução, apenas ponto de salto
     *
     * Uso:
     *   auto lbl = func.newLabel();
     *   func.jmp(lbl);
     *   func.appendLabel(lbl);
     */
    MirOp newLabel()
    {
        auto lbl = MIR_new_label(_ctx);
        return MirOp.fromRaw(MIR_new_label_op(_ctx, lbl));
    }

    /**
     * Insere o label `lbl` na posição atual do fluxo de instruções.
     *
     * Assembly gerado:
     *   L42:
     *
     * Uso:
     *   func.appendLabel(lbl);
     */
    void appendLabel(MirOp lbl)
    {
        MIR_append_insn(_ctx, _item, lbl.raw.u.label);
    }

    // -------------------------------------------------------------------------
    // Construção de operandos imediatos / memória (fábrica local)
    // -------------------------------------------------------------------------

    /// Operando inteiro imediato.  Uso: func.imm(42)
    MirOp imm(long v)
    {
        return MirOp.fromRaw(MIR_new_int_op(_ctx, v));
    }
    /// Operando inteiro sem sinal imediato.  Uso: func.uimm(0xDEAD_BEEF)
    MirOp uimm(ulong v)
    {
        return MirOp.fromRaw(MIR_new_uint_op(_ctx, v));
    }
    /// Operando float imediato.
    MirOp fimm(float v)
    {
        return MirOp.fromRaw(MIR_new_float_op(_ctx, v));
    }
    /// Operando double imediato.
    MirOp dimm(double v)
    {
        return MirOp.fromRaw(MIR_new_double_op(_ctx, v));
    }

    /**
     * Operando de memória: [base + index*scale + disp] com tipo `type`.
     *
     * Exemplo de acesso 64-bit:
     *   func.mem(MIR_T_I64, rBase, MirOp.init, 1, 8)
     *   ; mov rDest, qword [rBase + 8]
     */
    MirOp mem(MIR_type_t type, MirOp base,
        MirOp index = MirOp.init,
        MIR_scale_t scale = 1,
        MIR_disp_t disp = 0)
    {
        auto baseReg = base.raw.u.reg;
        auto indexReg = index == MirOp.init ? 0 : index.raw.u.reg;
        return MirOp.fromRaw(
            MIR_new_mem_op(_ctx, type, disp, baseReg, indexReg, scale));
    }

    // -------------------------------------------------------------------------
    // Emissão de instruções — Moves
    // -------------------------------------------------------------------------

    /**
     * MOV dest, src  — copia inteiro de 64 bits.
     *
     * Assembly gerado:
     *   mov  rax, rbx      ; (ou equivalente na ABI alvo)
     *
     * Uso:
     *   func.mov(rDest, rSrc);
     *   func.mov(rDest, func.imm(0));   // zera registrador
     */
    void mov(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_MOV, dest, src);
    }

    /// FMOV — copia float de 32 bits.
    void fmov(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_FMOV, dest, src);
    }
    /// DMOV — copia double de 64 bits.
    void dmov(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_DMOV, dest, src);
    }

    // -------------------------------------------------------------------------
    // Aritmética inteira
    // -------------------------------------------------------------------------

    /**
     * ADD dest, a, b  — adição inteira 64 bits.
     *
     * Assembly gerado:
     *   add  rax, rbx      ; dest = a + b
     *
     * Uso:
     *   func.add(rRes, rA, rB);
     *   func.add(rRes, rA, func.imm(1));  // incremento
     */
    void add(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_ADD, dest, a, b);
    }

    /**
     * SUB dest, a, b  — subtração inteira 64 bits.
     *
     * Assembly gerado:
     *   sub  rax, rbx
     */
    void sub(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_SUB, dest, a, b);
    }

    /**
     * MUL dest, a, b  — multiplicação inteira 64 bits (com sinal).
     *
     * Assembly gerado:
     *   imul rax, rbx
     */
    void mul(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_MUL, dest, a, b);
    }

    /**
     * DIV dest, a, b  — divisão inteira 64 bits com sinal.
     *
     * Assembly gerado:
     *   cqo
     *   idiv rbx           ; dest = a / b
     */
    void div(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_DIV, dest, a, b);
    }

    /**
     * MOD dest, a, b  — resto inteiro 64 bits com sinal.
     *
     * Assembly gerado:
     *   cqo
     *   idiv rbx           ; dest = a % b  (rdx)
     */
    void mod(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_MOD, dest, a, b);
    }

    /// UDIV — divisão sem sinal 64 bits.  (div rbx)
    void udiv(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_UDIV, dest, a, b);
    }
    /// UMOD — resto sem sinal 64 bits.
    void umod(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_UMOD, dest, a, b);
    }

    /// NEG dest, src  — negação inteira.  (neg rax)
    void neg(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_NEG, dest, src);
    }

    // -------------------------------------------------------------------------
    // Aritmética de ponto flutuante
    // -------------------------------------------------------------------------

    /// FADD — adição float 32 bits.  (addss xmm0, xmm1)
    void fadd(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_FADD, dest, a, b);
    }
    /// DADD — adição double 64 bits.  (addsd xmm0, xmm1)
    void dadd(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_DADD, dest, a, b);
    }
    /// FSUB — subtração float.  (subss xmm0, xmm1)
    void fsub(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_FSUB, dest, a, b);
    }
    /// DSUB — subtração double.  (subsd xmm0, xmm1)
    void dsub(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_DSUB, dest, a, b);
    }
    /// FMUL — multiplicação float.  (mulss xmm0, xmm1)
    void fmul(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_FMUL, dest, a, b);
    }
    /// DMUL — multiplicação double.  (mulsd xmm0, xmm1)
    void dmul(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_DMUL, dest, a, b);
    }
    /// FDIV — divisão float.  (divss xmm0, xmm1)
    void fdiv(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_FDIV, dest, a, b);
    }
    /// DDIV — divisão double.  (divsd xmm0, xmm1)
    void ddiv(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_DDIV, dest, a, b);
    }

    // -------------------------------------------------------------------------
    // Lógica e deslocamentos
    // -------------------------------------------------------------------------

    /// AND dest, a, b  (and rax, rbx)
    void and_(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_AND, dest, a, b);
    }
    /// OR  dest, a, b  (or  rax, rbx)
    void or_(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_OR, dest, a, b);
    }
    /// XOR dest, a, b  (xor rax, rbx)
    void xor_(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_XOR, dest, a, b);
    }
    /// LSH dest, a, b  — left shift lógico.  (shl rax, cl)
    void lsh(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_LSH, dest, a, b);
    }
    /// RSH dest, a, b  — right shift aritmético.  (sar rax, cl)
    void rsh(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_RSH, dest, a, b);
    }
    /// URSH dest, a, b — right shift lógico sem sinal.  (shr rax, cl)
    void ursh(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_URSH, dest, a, b);
    }

    // -------------------------------------------------------------------------
    // Comparações (produzem 0/1 em inteiro)
    // -------------------------------------------------------------------------

    /// EQ  dest, a, b  — dest = (a == b) ? 1 : 0  (sete + movzx)
    void eq(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_EQ, dest, a, b);
    }
    /// NE  dest, a, b  — dest = (a != b) ? 1 : 0
    void ne(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_NE, dest, a, b);
    }
    /// LT  dest, a, b  — dest = (a <  b) ? 1 : 0 com sinal  (setl)
    void lt(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_LT, dest, a, b);
    }
    /// LE  dest, a, b  — dest = (a <= b) ? 1 : 0 com sinal  (setle)
    void le(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_LE, dest, a, b);
    }
    /// GT  dest, a, b  — dest = (a >  b) ? 1 : 0 com sinal  (setg)
    void gt(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_GT, dest, a, b);
    }
    /// GE  dest, a, b  — dest = (a >= b) ? 1 : 0 com sinal  (setge)
    void ge(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_GE, dest, a, b);
    }
    /// ULT — menor sem sinal.  (setb)
    void ult(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_ULT, dest, a, b);
    }
    /// ULE — menor-ou-igual sem sinal.  (setbe)
    void ule(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_ULE, dest, a, b);
    }
    /// UGT — maior sem sinal.  (seta)
    void ugt(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_UGT, dest, a, b);
    }
    /// UGE — maior-ou-igual sem sinal.  (setae)
    void uge(MirOp dest, MirOp a, MirOp b)
    {
        _emit3(MIR_insn_code_t.MIR_UGE, dest, a, b);
    }

    // -------------------------------------------------------------------------
    // Branches / saltos
    // -------------------------------------------------------------------------

    /**
     * JMP label  — salto incondicional.
     *
     * Assembly gerado:
     *   jmp  .L42
     *
     * Uso:
     *   func.jmp(loopLabel);
     */
    void jmp(MirOp label)
    {
        MIR_op_t[1] ops = [label.raw];
        MIR_append_insn(_ctx, _item,
            MIR_new_insn_arr(_ctx, MIR_insn_code_t.MIR_JMP, 1, ops.ptr));
    }

    /**
     * BT label, cond  — branch se cond != 0 (Branch if True).
     *
     * Assembly gerado:
     *   test rax, rax
     *   jnz  .L42
     *
     * Uso:
     *   func.bt(exitLabel, rCond);
     */
    void bt(MirOp label, MirOp cond)
    {
        MIR_op_t[2] ops = [label.raw, cond.raw];
        MIR_append_insn(_ctx, _item,
            MIR_new_insn_arr(_ctx, MIR_insn_code_t.MIR_BT, 2, ops.ptr));
    }

    /**
     * BF label, cond  — branch se cond == 0 (Branch if False).
     *
     * Assembly gerado:
     *   test rax, rax
     *   jz   .L42
     *
     * Uso:
     *   func.bf(skipLabel, rCond);
     */
    void bf(MirOp label, MirOp cond)
    {
        MIR_op_t[2] ops = [label.raw, cond.raw];
        MIR_append_insn(_ctx, _item,
            MIR_new_insn_arr(_ctx, MIR_insn_code_t.MIR_BF, 2, ops.ptr));
    }

    /**
     * BEQ label, a, b  — branch se a == b.
     *
     * Assembly gerado:
     *   cmp  rax, rbx
     *   je   .L42
     */
    void beq(MirOp label, MirOp a, MirOp b)
    {
        _branchCmp(MIR_insn_code_t.MIR_BEQ, label, a, b);
    }
    /// BNE — branch se a != b.  (jne .Lxx)
    void bne(MirOp label, MirOp a, MirOp b)
    {
        _branchCmp(MIR_insn_code_t.MIR_BNE, label, a, b);
    }
    /// BLT — branch se a <  b com sinal.  (jl .Lxx)
    void blt(MirOp label, MirOp a, MirOp b)
    {
        _branchCmp(MIR_insn_code_t.MIR_BLT, label, a, b);
    }
    /// BLE — branch se a <= b com sinal.  (jle .Lxx)
    void ble(MirOp label, MirOp a, MirOp b)
    {
        _branchCmp(MIR_insn_code_t.MIR_BLE, label, a, b);
    }
    /// BGT — branch se a >  b com sinal.  (jg .Lxx)
    void bgt(MirOp label, MirOp a, MirOp b)
    {
        _branchCmp(MIR_insn_code_t.MIR_BGT, label, a, b);
    }
    /// BGE — branch se a >= b com sinal.  (jge .Lxx)
    void bge(MirOp label, MirOp a, MirOp b)
    {
        _branchCmp(MIR_insn_code_t.MIR_BGE, label, a, b);
    }
    /// UBLT — branch se a <  b sem sinal.  (jb .Lxx)
    void ublt(MirOp label, MirOp a, MirOp b)
    {
        _branchCmp(MIR_insn_code_t.MIR_UBLT, label, a, b);
    }
    /// UBLE — branch se a <= b sem sinal.  (jbe .Lxx)
    void uble(MirOp label, MirOp a, MirOp b)
    {
        _branchCmp(MIR_insn_code_t.MIR_UBLE, label, a, b);
    }

    // -------------------------------------------------------------------------
    // Chamadas de função
    // -------------------------------------------------------------------------

    /**
     * Emite uma instrução CALL.
     *
     * Parâmetros:
     *   proto   — operando de referência ao protótipo (MIR_proto_item).
     *   callee  — operando de referência à função a chamar.
     *   results — slice de operandos de resultado (pode ser vazio).
     *   args    — slice de operandos de argumento.
     *
     * Assembly gerado (System V AMD64):
     *   ; argumentos já em rdi, rsi, rdx, rcx, r8, r9 (inteiros)
     *   call  <callee>
     *   ; resultados em rax (e rdx para 128-bit)
     *
     * Uso:
     *   func.call(protoOp, calleeOp, [rRes], [rArg0, rArg1]);
     */
    void call(MirOp proto, MirOp callee,
        MirOp[] results, MirOp[] args)
    {
        // Layout: proto, callee, results..., args...
        size_t total = 2 + results.length + args.length;

        // Usamos um buffer estático para evitar alocação dinâmica ().
        // Limite prático de 32 ops por call — suficiente para funções reais.
        enum MAX_OPS = 32;
        assert(total <= MAX_OPS);

        MIR_op_t[MAX_OPS] ops;
        ops[0] = proto.raw;
        ops[1] = callee.raw;
        foreach (i, r; results)
            ops[2 + i] = r.raw;
        foreach (i, a; args)
            ops[2 + results.length + i] = a.raw;

        MIR_append_insn(_ctx, _item,
            MIR_new_insn_arr(_ctx, MIR_insn_code_t.MIR_CALL, total, ops.ptr));
    }

    // -------------------------------------------------------------------------
    // Retorno
    // -------------------------------------------------------------------------

    /**
     * RET ops...  — retorna zero ou mais valores.
     *
     * Assembly gerado:
     *   ; valor em rax (inteiro) ou xmm0 (float/double)
     *   ret
     *
     * Uso:
     *   func.ret(rResult);          // retorno simples
     *   func.ret();                 // void return
     *   func.ret(rHi, rLo);        // dois valores de retorno
     */
    void ret(MirOp[] vals...)
    {
        enum MAX_RET = 8;
        assert(vals.length <= MAX_RET);
        MIR_op_t[MAX_RET] ops;
        foreach (i, v; vals)
            ops[i] = v.raw;
        MIR_append_insn(_ctx, _item,
            MIR_new_insn_arr(_ctx, MIR_insn_code_t.MIR_RET, vals.length, ops.ptr));
    }

    // -------------------------------------------------------------------------
    // Alocação de pilha
    // -------------------------------------------------------------------------

    /**
     * ALLOCA dest, size  — aloca `size` bytes na pilha e armazena o ponteiro
     * em `dest`.
     *
     * Assembly gerado:
     *   sub  rsp, <size>
     *   mov  rax, rsp      ; dest recebe endereço
     *
     * Uso:
     *   auto rPtr = func.newReg("buf", MIR_T_P);
     *   func.alloca(rPtr, func.imm(64));   // 64 bytes na pilha
     */
    void alloca_(MirOp dest, MirOp size)
    {
        _emit2(MIR_insn_code_t.MIR_ALLOCA, dest, size);
    }

    // -------------------------------------------------------------------------
    // Extensões de inteiro
    // -------------------------------------------------------------------------

    /// EXT8  — estende sinal de 8 bits para 64 bits.  (movsx rax, al)
    void ext8(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_EXT8, dest, src);
    }
    /// EXT16 — estende sinal de 16 bits para 64 bits.  (movsx rax, ax)
    void ext16(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_EXT16, dest, src);
    }
    /// EXT32 — estende sinal de 32 bits para 64 bits.  (movsxd rax, eax)
    void ext32(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_EXT32, dest, src);
    }
    /// UEXT8  — estende zero de 8 bits.  (movzx rax, al)
    void uext8(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_UEXT8, dest, src);
    }
    /// UEXT16 — estende zero de 16 bits.  (movzx rax, ax)
    void uext16(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_UEXT16, dest, src);
    }
    /// UEXT32 — estende zero de 32 bits.  (mov eax, eax — implícito no x86-64)
    void uext32(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_UEXT32, dest, src);
    }

    // -------------------------------------------------------------------------
    // Conversões inteiro <-> ponto flutuante
    // -------------------------------------------------------------------------

    /// I2F  — int64 → float.   (cvtsi2ss xmm0, rax)
    void i2f(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_I2F, dest, src);
    }
    /// I2D  — int64 → double.  (cvtsi2sd xmm0, rax)
    void i2d(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_I2D, dest, src);
    }
    /// F2I  — float  → int64.  (cvttss2si rax, xmm0)
    void f2i(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_F2I, dest, src);
    }
    /// D2I  — double → int64.  (cvttsd2si rax, xmm0)
    void d2i(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_D2I, dest, src);
    }
    /// F2D  — float  → double. (cvtss2sd xmm0, xmm1)
    void f2d(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_F2D, dest, src);
    }
    /// D2F  — double → float.  (cvtsd2ss xmm0, xmm1)
    void d2f(MirOp dest, MirOp src)
    {
        _emit2(MIR_insn_code_t.MIR_D2F, dest, src);
    }

    // -------------------------------------------------------------------------
    // Instrução genérica de baixo nível (escape hatch)
    // -------------------------------------------------------------------------

    /**
     * Emite uma instrução arbitrária com operandos explícitos.
     *
     * Use quando nenhum método de alto nível cobre o opcode necessário.
     *
     * Uso:
     *   func.emit(MIR_insn_code_t.MIR_PRSET, [dest.raw, src.raw]);
     */
    void emit(MIR_insn_code_t code, MIR_op_t[] ops)
    {
        MIR_append_insn(_ctx, _item,
            MIR_new_insn_arr(_ctx, code, ops.length, ops.ptr));
    }

    // -------------------------------------------------------------------------
    // Encerramento
    // -------------------------------------------------------------------------

    /**
     * Finaliza a construção da função.
     *
     * Deve ser chamado exatamente uma vez após todas as instruções serem
     * emitidas. Após finish() o objeto MirFunc não deve ser mais usado
     * para emissão.
     *
     * Mapeia para: MIR_finish_func(ctx)
     */
    void finish()
    {
        MIR_finish_func(_ctx);
    }

    // -------------------------------------------------------------------------
    // Debug / saída textual
    // -------------------------------------------------------------------------

    /**
     * Imprime a função em formato textual MIR no arquivo `f`.
     *
     * Uso:
     *   import core.stdc.stdio : stdout;
     *   func.dump(stdout);
     */
    void dump(FILE* f)
    {
        MIR_output_item(_ctx, cast(void*) f, _item);
    }

    // =========================================================================
    // Helpers privados de emissão
    // =========================================================================

private:
    void _emit2(MIR_insn_code_t code, MirOp a, MirOp b)
    {
        MIR_op_t[2] ops = [a.raw, b.raw];
        MIR_append_insn(_ctx, _item,
            MIR_new_insn_arr(_ctx, code, 2, ops.ptr));
    }

    void _emit3(MIR_insn_code_t code, MirOp d, MirOp a, MirOp b)
    {
        MIR_op_t[3] ops = [d.raw, a.raw, b.raw];
        MIR_append_insn(_ctx, _item,
            MIR_new_insn_arr(_ctx, code, 3, ops.ptr));
    }

    void _branchCmp(MIR_insn_code_t code,
        MirOp label, MirOp a, MirOp b)
    {
        MIR_op_t[3] ops = [label.raw, a.raw, b.raw];
        MIR_append_insn(_ctx, _item,
            MIR_new_insn_arr(_ctx, code, 3, ops.ptr));
    }
}

// =============================================================================
// MirModule — agrupa funções, dados e protótipos
// =============================================================================

/**
 * MirModule representa um módulo MIR — a unidade de compilação/linkagem.
 *
 * Um módulo contém funções, protótipos, dados e importações/exportações.
 *
 * Ciclo de vida:
 *   1. Criado via MirContext.newModule().
 *   2. Funções e itens adicionados com os métodos abaixo.
 *   3. Encerrado com finish().
 *   4. Carregado e linkado via MirContext.load() / MirContext.link().
 */
final class MirModule
{
private:
    MIR_context_t _ctx;
    MIR_module_t _mod;

public:
    /// Construído internamente por MirContext.
    this(MIR_context_t ctx, MIR_module_t mod)
    {
        _ctx = ctx;
        _mod = mod;
    }

    /// Módulo C subjacente.
    MIR_module_t mod()
    {
        return _mod;
    }

    // -------------------------------------------------------------------------
    // Declaração de funções
    // -------------------------------------------------------------------------

    /**
     * Cria uma nova função no módulo.
     *
     * Parâmetros:
     *   name      — nome C da função (usado na linkagem).
     *   resTypes  — tipos de retorno (array; use [] para void).
     *   params    — parâmetros (nome + tipo); construa com MIR_var().
     *
     * Retorna MirFunc para emissão de instruções.
     *
     * Uso:
     *   MIR_type_t[1] res = [MIR_T_I64];
     *   MIR_var_t[2]  par = [MIR_var("a", MIR_T_I64), MIR_var("b", MIR_T_I64)];
     *   auto f = mod.newFunc("soma", res, par);
     */
    MirFunc newFunc(const(char)* name,
        MIR_type_t[] resTypes,
        MIR_var_t[] params)
    {
        auto item = MIR_new_func_arr(_ctx, name,
            resTypes.length, resTypes.ptr,
            params.length, params.ptr);
        return new MirFunc(_ctx, item);
    }

    /**
     * Cria uma função vararg (aceita número variável de argumentos após
     * os parâmetros fixos declarados).
     *
     * Uso:
     *   auto f = mod.newVarArgFunc("printf", [], [MIR_var("fmt", MIR_T_P)]);
     */
    MirFunc newVarArgFunc(const(char)* name,
        MIR_type_t[] resTypes,
        MIR_var_t[] params)
    {
        auto item = MIR_new_vararg_func_arr(_ctx, name,
            resTypes.length, resTypes.ptr,
            params.length, params.ptr);
        return new MirFunc(_ctx, item);
    }

    // -------------------------------------------------------------------------
    // Declaração de protótipos (para CALL)
    // -------------------------------------------------------------------------

    /**
     * Cria um protótipo de função (usado como primeiro operando de CALL).
     *
     * Uso:
     *   auto proto = mod.newProto("soma_proto",
     *                             [MIR_T_I64],
     *                             [MIR_var("a", MIR_T_I64), MIR_var("b", MIR_T_I64)]);
     *   // depois: func.call(MirOp.fromRaw(MIR_new_ref_op(ctx, proto)), ...)
     */
    MIR_item_t newProto(const(char)* name,
        MIR_type_t[] resTypes,
        MIR_var_t[] params)
    {
        return MIR_new_proto_arr(_ctx, name,
            resTypes.length, resTypes.ptr,
            params.length, params.ptr);
    }

    /// Protótipo vararg.
    MIR_item_t newVarArgProto(const(char)* name,
        MIR_type_t[] resTypes,
        MIR_var_t[] params)
    {
        return MIR_new_vararg_proto_arr(_ctx, name,
            resTypes.length, resTypes.ptr,
            params.length, params.ptr);
    }

    // -------------------------------------------------------------------------
    // Importações / exportações
    // -------------------------------------------------------------------------

    /**
     * Declara um símbolo externo importado (resolvido na linkagem).
     *
     * Uso:
     *   mod.import_("printf");   // importa printf da libc
     */
    MIR_item_t import_(const(char)* name)
    {
        return MIR_new_import(_ctx, name);
    }

    /**
     * Exporta um símbolo definido neste módulo para outros módulos.
     *
     * Uso:
     *   mod.export_("minha_func");
     */
    MIR_item_t export_(const(char)* name)
    {
        return MIR_new_export(_ctx, name);
    }

    /// Forward — declara símbolo cujo item virá mais adiante no módulo.
    MIR_item_t forward(const(char)* name)
    {
        return MIR_new_forward(_ctx, name);
    }

    // -------------------------------------------------------------------------
    // Dados estáticos
    // -------------------------------------------------------------------------

    /**
     * Cria um bloco de dados inicializados com `nel` elementos do tipo
     * `elType`.
     *
     * Uso:
     *   long[3] vals = [1, 2, 3];
     *   mod.newData("tabela", MIR_T_I64, 3, vals.ptr);
     */
    MIR_item_t newData(const(char)* name, MIR_type_t elType,
        size_t nel, const void* els)
    {
        return MIR_new_data(_ctx, name, elType, nel, els);
    }

    /**
     * Cria um bloco BSS (memória zerada) de `len` bytes.
     *
     * Uso:
     *   mod.newBss("buffer", 4096);
     */
    MIR_item_t newBss(const(char)* name, size_t len)
    {
        return MIR_new_bss(_ctx, name, len);
    }

    /**
     * Cria um item de dado string (null-terminated incluído automaticamente).
     *
     * Uso:
     *   MIR_str_t s; s.s = "Hello, World!\n"; s.len = 15;
     *   mod.newStringData("msg", s);
     */
    MIR_item_t newStringData(const(char)* name, MIR_str_t str)
    {
        return MIR_new_string_data(_ctx, name, str);
    }

    // -------------------------------------------------------------------------
    // Encerramento
    // -------------------------------------------------------------------------

    /**
     * Finaliza a definição do módulo.
     * Deve ser chamado antes de MirContext.load().
     */
    void finish()
    {
        MIR_finish_module(_ctx);
    }

    // -------------------------------------------------------------------------
    // Debug
    // -------------------------------------------------------------------------

    /// Imprime o módulo completo em formato textual MIR.
    void dump(FILE* f)
    {
        MIR_output_module(_ctx, cast(void*) f, _mod);
    }
}

// =============================================================================
// MirJit — wraps mir-gen.h (geração de código nativo)
// =============================================================================

/**
 * MirJit controla o gerador de código nativo (JIT) da libmir.
 *
 * Obtido via MirContext.jit().
 *
 * Ciclo de vida:
 *   1. Chamar jit.init() após MirContext.link().
 *   2. Compilar funções com jit.compile(func).
 *   3. Obter ponteiro nativo com jit.getCode!T(func).
 *   4. Chamar jit.finish() ao final.
 */
final class MirJit
{
private:
    MIR_context_t _ctx;

public:
    this(MIR_context_t ctx)
    {
        _ctx = ctx;
    }

    /**
     * Inicializa o subsistema de geração de código nativo.
     *
     * Deve ser chamado antes de qualquer compile() ou setInterface().
     */
    void init()
    {
        MIR_gen_init(_ctx);
    }

    /**
     * Define o nível de otimização (0 = sem otimização, 3 = máxima).
     *
     * Padrão: 2.
     *
     * Uso:
     *   jit.setOptLevel(3);
     */
    void setOptLevel(uint level)
    {
        MIR_gen_set_optimize_level(_ctx, level);
    }

    /**
     * Compila `func` para código nativo e retorna o ponteiro da função.
     *
     * O parâmetro de template `F` deve ser o tipo do ponteiro de função
     * esperado.
     *
     * Uso:
     *   alias SomaTipo = extern(C) long function(long, long)  ;
     *   auto soma = jit.compile!SomaTipo(funcItem);
     *   long r = soma(3, 4);  // r == 7
     */
    F compile(F)(MirFunc func, int genNum = 0)
    {
        return cast(F) MIR_gen(_ctx, func.item);
    }

    /**
     * Versão raw de compile() que retorna void* (sem tipagem).
     *
     * Útil quando o tipo de função é desconhecido em tempo de compilação.
     */
    void* compileRaw(MirFunc func)
    {
        return MIR_gen(_ctx, func.item);
    }

    /**
     * Define a interface JIT para a função (chamada automática durante link
     * lazy). Necessário antes de chamar MirContext.link() com interface lazy.
     */
    void setInterface(MirFunc func)
    {
        MIR_set_gen_interface(_ctx, func.item);
    }

    /**
     * Define a interface de geração lazy (compilação sob demanda).
     */
    void setLazyInterface(MirFunc func)
    {
        MIR_set_lazy_gen_interface(_ctx, func.item);
    }

    /**
     * Define arquivo de debug para o gerador `genNum`.
     * Imprime IR intermediária e código gerado.
     */
    void setDebugFile(FILE* f, int genNum = 0)
    {
        MIR_gen_set_debug_file(_ctx, genNum, cast(void*) f);
    }

    /**
     * Define nível de verbosidade de debug (0 = silencioso, 3 = máximo).
     */
    void setDebugLevel(int level, int genNum = 0)
    {
        MIR_gen_set_debug_level(_ctx, genNum, level);
    }

    /**
     * Libera todos os recursos do gerador JIT.
     * Deve ser chamado antes de MirContext.finish().
     */
    void finish()
    {
        MIR_gen_finish(_ctx);
    }
}

// =============================================================================
// MirContext — raiz de tudo
// =============================================================================

/**
 * MirContext é o ponto de entrada principal da API MIR de alto nível.
 *
 * Encapsula MIR_context_t e gerencia o ciclo de vida completo:
 * inicialização, criação de módulos, linkagem e JIT.
 *
 * Exemplo completo — função "quadrado" JIT-compilada:
 * ---
 * auto ctx  = new MirContext();
 * auto mod  = ctx.newModule("exemplo");
 *
 * MIR_type_t[1] resT = [MIR_type_t.MIR_T_I64];
 * MIR_var_t[1]  parV = [MIR_var("n", MIR_type_t.MIR_T_I64)];
 * auto func = mod.newFunc("quadrado", resT, parV);
 *
 * auto rN   = func.reg("n");
 * auto rRes = func.newReg("res", MIR_type_t.MIR_T_I64);
 * func.mul(rRes, rN, rN);
 * func.ret(rRes);
 * func.finish();
 * mod.finish();
 *
 * ctx.load(mod);
 * ctx.link();
 *
 * auto jit = ctx.jit();
 * jit.init();
 * alias QuadT = extern(C) long function(long)  ;
 * auto quadrado = jit.compile!QuadT(func);
 * assert(quadrado(7) == 49);
 * jit.finish();
 * ctx.finish();
 * ---
 */
final class MirContext
{
private:
    MIR_context_t _ctx;

public:
    /**
     * Inicializa o contexto MIR com alocador e code-allocator padrão.
     *
     * Verifica a versão da API em tempo de execução e aborta se incompatível.
     */
    this()
    {
        _ctx = MIR_init();
    }

    /**
     * Inicializa com alocadores customizados.
     *
     * Útil para integrar com arenas de memória personalizadas.
     *
     * Uso:
     *   auto ctx = new MirContext(myAlloc, null);
     */
    this(MIR_alloc_t alloc, MIR_code_alloc_t codeAlloc)
    {
        _ctx = MIR_init2(alloc, codeAlloc);
    }

    /// Contexto C subjacente (para interoperabilidade direta).
    MIR_context_t ctx()
    {
        return _ctx;
    }

    // -------------------------------------------------------------------------
    // Módulos
    // -------------------------------------------------------------------------

    /**
     * Cria e retorna um novo módulo de nome `name`.
     *
     * Apenas um módulo pode estar aberto por vez (restrição da libmir).
     *
     * Uso:
     *   auto mod = ctx.newModule("meu_app");
     */
    MirModule newModule(const(char)* name)
    {
        auto m = MIR_new_module(_ctx, name);
        return new MirModule(_ctx, m);
    }

    // -------------------------------------------------------------------------
    // Linkagem
    // -------------------------------------------------------------------------

    /**
     * Carrega um módulo finalizado no contexto de linkagem.
     *
     * Deve ser chamado após mod.finish() e antes de link().
     *
     * Uso:
     *   ctx.load(mod);
     */
    void load(MirModule mod)
    {
        MIR_load_module(_ctx, mod.mod);
    }

    /**
     * Registra um símbolo externo (ex.: função da libc) para resolução.
     *
     * Uso:
     *   import core.stdc.stdio : printf;
     *   ctx.loadExternal("printf", cast(void*) &printf);
     */
    void loadExternal(const(char)* name, void* addr)
    {
        MIR_load_external(_ctx, name, addr);
    }

    /**
     * Executa a linkagem de todos os módulos carregados.
     *
     * `setInterface`   — callback para definir interface de execução por item
     *                    (use null para o padrão de intérprete).
     * `importResolver` — callback para resolver símbolos não encontrados
     *                    (use null para emitir erro).
     *
     * Uso simples (intérprete):
     *   ctx.link();
     *
     * Uso com JIT:
     *   ctx.link(&MIR_set_gen_interface, null);
     */
    void link(void function(MIR_context_t, MIR_item_t) setInterface = null,
        void* function(const(char)*) importResolver = null)
    {
        MIR_link(_ctx, setInterface, importResolver);
    }

    // -------------------------------------------------------------------------
    // JIT
    // -------------------------------------------------------------------------

    /**
     * Retorna um MirJit associado a este contexto.
     *
     * Você deve chamar jit.init() antes de usar o JIT.
     *
     * Uso:
     *   auto jit = ctx.jit();
     *   jit.init();
     */
    MirJit jit()
    {
        return new MirJit(_ctx);
    }

    // -------------------------------------------------------------------------
    // Intérprete
    // -------------------------------------------------------------------------

    /**
     * Interpreta `func` com os argumentos `args` e armazena os resultados
     * em `results`.
     *
     * Útil para depuração sem JIT.
     *
     * Uso:
     *   MIR_val_t[1] res;
     *   MIR_val_t[2] args;
     *   args[0].i = 3;
     *   args[1].i = 4;
     *   ctx.interp(func, res[], args[]);
     *   // res[0].i == 7
     */
    void interp(MirFunc func,
        MIR_val_t[] results,
        MIR_val_t[] args)
    {
        MIR_interp_arr(_ctx, func.item,
            results.ptr, args.length, args.ptr);
    }

    /**
     * Configura a interface de intérprete para `func`.
     * Necessário antes de chamar interp() quando se usa linkagem com
     * interface customizada.
     */
    void setInterpInterface(MirFunc func)
    {
        MIR_set_interp_interface(_ctx, func.item);
    }

    // -------------------------------------------------------------------------
    // Erro
    // -------------------------------------------------------------------------

    /**
     * Define uma função de tratamento de erros customizada.
     *
     * A função padrão imprime para stderr e chama abort().
     *
     * Uso:
     *   extern(C) void meuErro(MIR_error_type_t t, const(char)* fmt, ...)   {
     *       // tratar...
     *   }
     *   ctx.setErrorFunc(&meuErro);
     */
    void setErrorFunc(MIR_error_func_t f)
    {
        MIR_set_error_func(_ctx, f);
    }

    /// Retorna a função de erro atual.
    MIR_error_func_t getErrorFunc()
    {
        return MIR_get_error_func(_ctx);
    }

    // -------------------------------------------------------------------------
    // I/O textual e binário
    // -------------------------------------------------------------------------

    /**
     * Imprime todos os módulos no contexto em formato textual MIR.
     *
     * Útil para inspecionar o IR gerado antes da compilação.
     *
     * Uso:
     *   import core.stdc.stdio : stdout;
     *   ctx.dump(stdout);
     */
    void dump(FILE* f)
    {
        MIR_output(_ctx, cast(void*) f);
    }

    /**
     * Serializa todos os módulos em formato binário compacto MIR.
     *
     * Uso:
     *   auto f = fopen("saida.mirb", "wb");
     *   ctx.write(f);
     *   fclose(f);
     */
    void write(FILE* f)
    {
        MIR_write(_ctx, cast(void*) f);
    }

    /**
     * Lê e desserializa módulos do formato binário MIR.
     *
     * Uso:
     *   auto f = fopen("saida.mirb", "rb");
     *   ctx.read(f);
     *   fclose(f);
     */
    void read(FILE* f)
    {
        MIR_read(_ctx, cast(void*) f);
    }

    /**
     * Lê e compila módulos a partir de uma string no formato textual MIR.
     *
     * Uso:
     *   ctx.scanString("m: module\n  func: ...\n  endfunc\nendmodule\n");
     */
    void scanString(const(char)* src)
    {
        MIR_scan_string(_ctx, src);
    }

    // -------------------------------------------------------------------------
    // Encerramento
    // -------------------------------------------------------------------------

    /**
     * Libera todos os recursos do contexto MIR.
     *
     * Deve ser a última operação realizada. Após finish() o objeto
     * MirContext e todos os objetos derivados (módulos, funções) tornam-se
     * inválidos.
     */
    void finish()
    {
        MIR_finish(_ctx);
    }
}

// =============================================================================
// Módulo-nível: fábrica de operandos sem contexto de função
// (para uso na construção de chamadas e dados)
// =============================================================================

/**
 * Constrói um operando de referência a um item (função/proto/dado).
 *
 * Necessário para passar funções como operandos de CALL.
 *
 * Uso:
 *   auto protoOp = mirRef(ctx.ctx, protoItem);
 *   func.call(protoOp, mirRef(ctx.ctx, funcItem), [], args);
 */
MirOp mirRef(MIR_context_t ctx, MIR_item_t item)
{
    return MirOp.fromRaw(MIR_new_ref_op(ctx, item));
}

/// Constrói operando inteiro imediato sem contexto de função.
MirOp mirImm(MIR_context_t ctx, long v)
{
    return MirOp.fromRaw(MIR_new_int_op(ctx, v));
}

/// Constrói operando uint imediato sem contexto de função.
MirOp mirUimm(MIR_context_t ctx, ulong v)
{
    return MirOp.fromRaw(MIR_new_uint_op(ctx, v));
}
