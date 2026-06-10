module backend.jit.codegen;

import main : checkpoint;

import core.stdc.stdio : fprintf, stderr, stdout;
import core.stdc.stdlib : abort;

import std.datetime.stopwatch;
import std.algorithm;
import std.format;
import std.array;
import std.stdio;
import std.conv;

import backend.jit.mir_api;
import type_registry;
import htype;
import utils;
import token;
import ast;

struct MirVarValue
{
    MirOp var;
    MIR_type_t type;
    bool isPtr;
}

struct MirFnValue
{
    string name;
    MirItem proto;
    MirFunc fn;
    MirVarValue[string] locals;
    MirVar[string] params;
    MirOp[string] labels;
    MirItem importItem;
}

// hash para strings
uint fnv1a(const(char)* s) pure nothrow @nogc
{
    uint hash = 2_166_136_261;
    while (*s)
        hash = (hash ^ *s++) * 16_777_619;
    return hash;
}

// resolve simbolos dinamicos
void* resolveSymbol(const(char)* name)
{
    version (Windows)
    {
        import core.sys.windows.windows : GetProcAddress, LoadLibraryA;

        // bibliotecas mais comuns
        static const(char)*[] dlls = [
            "msvcrt.dll",
            "kernel32.dll",
            "user32.dll",
        ];

        foreach (dll; dlls)
        {
            auto h = LoadLibraryA(dll);
            if (h is null)
                continue;
            void* ptr = GetProcAddress(h, name);
            if (ptr !is null)
                return ptr;
        }
        return null;
    }
    else version (Posix)
    {
        import core.sys.posix.dlfcn : dlsym;

        return dlsym(null, name);
    }
    else
    {
        return null;
    }
}

extern (C) void* resolver(const(char)* name)
{
    void* ptr = resolveSymbol(name);
    if (ptr is null)
        return cast(void*)&unresolvedStub;
    return ptr;
}

extern (C) void unresolvedStub()
{
    fprintf(stderr, "erro: símbolo externo não resolvido\n");
    abort();
}

class MIRCodeGen
{
private:
    MirContext ctx;
    MirModule mod;
    MirFnValue* fn = null; // função atual
    MirFnValue[string] functions;
    MirItem[uint] strings;
    uint contador;

    void localSet(string name, MirVarValue value)
    {
        fn.locals[name] = value;
    }

    MirVarValue* localGet(string name)
    {
        if (fn is null)
            return null;
        if (name !in fn.locals)
            return null;
        return name in fn.locals;
    }

    bool localExists(string name)
    {
        return localGet(name) !is null;
    }

    const(char)* temp(string prefix = "tmp_")
    {
        return cStr(prefix ~ to!string(contador++));
    }

    MirOp compile(Node node)
    {
        switch (node.kind)
        {
        case NodeKind.Program:
            Program p = cast(Program) node;
            for (uint i; i < p.decls.length; i++)
                compile(p.decls[i]);
            return MirOp.init;

        case NodeKind.FuncDecl:
            return compileFnDecl(cast(FuncDecl) node);

        case NodeKind.InstructionStmt:
            return compileInstr(cast(InstructionStmt) node);

        case NodeKind.IntLit:
            IntLit lit = cast(IntLit) node;
            return fn.fn.imm(lit.val);

        case NodeKind.DoubleLit:
            DoubleLit lit = cast(DoubleLit) node;
            return fn.fn.dimm(lit.val);

        case NodeKind.StringLit:
            StringLit lit = cast(StringLit) node;
            const(char)* slit = cStr(lit.val);
            uint hash = fnv1a(slit);

            if (hash in strings)
                return mirRef(ctx.ctx(), strings[hash]);

            auto name = temp("str");
            MirStr str = MirStr(lit.val.length + 1, slit);

            auto item = mod.newStringData(name, str);
            strings[hash] = item;

            return mirRef(ctx.ctx(), item);

        case NodeKind.StructDecl:
            return MirOp.init;

        case NodeKind.LabelStmt:
            LabelStmt label = cast(LabelStmt) node;
            fn.fn.appendLabel(fn.labels[label.name]);
            for (ulong i; i < label.body.length; i++)
                compile(label.body[i]);
            return MirOp.init;

        default:
            debugNode(node);
            hpy_erro("MIR: Node desconhecido.");
            return MirOp.init;
        }
    }

    string tryGetVarName(Node node)
    {
        hpy_validar(node.kind == NodeKind.IDentifier, "Esperado um nome para a variavel.");
        return (cast(IDentifier) node).val;
    }

    // carrega o valor apontado por v.var em um novo temp
    MirOp load(MirVarValue v)
    {
        if (!v.isPtr)
            return v.var;
        MirType rt = getRegType(v.type);
        MirOp r = fn.fn.newReg(temp("ld_"), rt);
        if (rt == MirType.MIR_T_F)
            fn.fn.fmov(r, fn.fn.mem(v.type, v.var));
        else if (rt == MirType.MIR_T_D)
            fn.fn.dmov(r, fn.fn.mem(v.type, v.var));
        else
            fn.fn.mov(r, fn.fn.mem(v.type, v.var));
        return r;
    }

    // salva o valor src na memória apontada por v.var
    void store(MirVarValue v, MirOp src)
    {
        MirType rt = getRegType(v.type);
        if (rt == MirType.MIR_T_F)
            fn.fn.fmov(v.isPtr ? fn.fn.mem(v.type, v.var) : v.var, src);
        else if (rt == MirType.MIR_T_D)
            fn.fn.dmov(v.isPtr ? fn.fn.mem(v.type, v.var) : v.var, src);
        else
            fn.fn.mov(v.isPtr ? fn.fn.mem(v.type, v.var) : v.var, src);
    }

    MirOp compileInstr(InstructionStmt node)
    {
        switch (node.kind)
        {
        case Instruction.Aloca:
            string name = tryGetVarName(node.a);
            MirType elemType = hToM(node.type);
            MirOp rPtr = fn.fn.newReg(temp(), MirType.MIR_T_I64);
            fn.fn.alloca(rPtr, fn.fn.imm(node.type.getSize()));
            localSet(name, MirVarValue(rPtr, elemType, true));
            return rPtr;

        case Instruction.Ret:
            string var = tryGetVarName(node.a);
            MirVarValue addr = *localGet(var);
            MirOp rVal = load(addr);
            fn.fn.ret([rVal]);
            return rVal;

        case Instruction.Ime:
            string var = tryGetVarName(node.a);
            MirVarValue addr = *localGet(var);
            MirOp value = compile(node.b);
            if (value.isRef())
            {
                MirOp rTmp = fn.fn.newReg(temp("ref_"), MirType.MIR_T_I64);
                fn.fn.mov(rTmp, value);
                store(addr, rTmp);
            }
            else
                store(addr, value);
            return addr.var;

        case Instruction.Setar:
            string estr = tryGetVarName(node.a);
            string fName = tryGetVarName(node.b);
            string val = tryGetVarName(node.c);

            if (node.type.kind != HTypeKind.Struct)
            {
                hpy_erro("Setar em um tipo inválido.");
                return MirOp.init;
            }

            MirVarValue addr1 = *localGet(estr);
            MirVarValue addr2 = *localGet(val);

            HTypeStruct type = cast(HTypeStruct) node.type;
            StructField* field = fName in type.fields;
            if (field is null)
            {
                hpy_erro("O Campo não existe.");
                return MirOp.init;
            }

            auto rStructPtr = fn.fn.newReg(temp("sptr_"), MirType.MIR_T_I64);
            fn.fn.mov(rStructPtr, addr1.var);
            auto rFieldPtr = fn.fn.newReg(temp("field_ptr_"), MirType.MIR_T_I64);
            fn.fn.add(rFieldPtr, rStructPtr, fn.fn.imm(field.offset));
            MirOp rVal2 = load(addr2);
            fn.fn.mov(fn.fn.mem(hToM(field.type), rFieldPtr), rVal2);
            return MirOp.init;

        case Instruction.Obter:
            string estr = tryGetVarName(node.a);
            string fName = tryGetVarName(node.b);
            string val = tryGetVarName(node.c);

            if (node.type.kind != HTypeKind.Struct)
            {
                hpy_erro("Obter em um tipo inválido.");
                return MirOp.init;
            }

            MirVarValue addr1 = *localGet(estr);
            MirVarValue addr2 = *localGet(val);

            HTypeStruct type2 = cast(HTypeStruct) node.type;
            StructField* field2 = fName in type2.fields;
            if (field2 is null)
            {
                hpy_erro("O Campo não existe.");
                return MirOp.init;
            }

            auto rStructPtr2 = fn.fn.newReg(temp("sptr_"), MirType.MIR_T_I64);
            fn.fn.mov(rStructPtr2, addr1.var);
            auto rFieldPtr2 = fn.fn.newReg(temp("field_ptr_"), MirType.MIR_T_I64);
            fn.fn.add(rFieldPtr2, rStructPtr2, fn.fn.imm(field2.offset));
            MirType ft = hToM(field2.type);
            MirType frt = getRegType(ft);
            auto rFVal = fn.fn.newReg(temp("fval_"), frt);
            fn.fn.mov(rFVal, fn.fn.mem(ft, rFieldPtr2));
            store(addr2, rFVal);
            return addr2.var;

        case Instruction.Aritmetica:
            string res = tryGetVarName(node.a);
            string x = tryGetVarName(node.b);
            string y = tryGetVarName(node.c);

            MirVarValue addr1 = *localGet(res);
            MirVarValue addr2 = *localGet(x);
            MirVarValue addr3 = *localGet(y);

            MirOp rA = load(addr2);
            MirOp rB = load(addr3);
            MirOp rR = fn.fn.newReg(temp("arith_"), getRegType(addr1.type));

            alias FnOP = extern (C) void delegate(MirOp, MirOp, MirOp);
            FnOP func = null;

            switch (node.op)
            {
            case TokenKind.Soma:
                func = &fn.fn.add;
                if (addr2.type == MirType.MIR_T_F)
                    func = &fn.fn.fadd;
                else if (addr2.type == MirType.MIR_T_D)
                    func = &fn.fn.dadd;
                break;
            case TokenKind.Sub:
                func = &fn.fn.sub;
                if (addr2.type == MirType.MIR_T_F)
                    func = &fn.fn.fsub;
                else if (addr2.type == MirType.MIR_T_D)
                    func = &fn.fn.dsub;
                break;
            case TokenKind.Mul:
                func = &fn.fn.mul;
                if (addr2.type == MirType.MIR_T_F)
                    func = &fn.fn.fmul;
                else if (addr2.type == MirType.MIR_T_D)
                    func = &fn.fn.dmul;
                break;
            case TokenKind.Div:
                func = &fn.fn.div;
                if (addr2.type == MirType.MIR_T_F)
                    func = &fn.fn.fdiv;
                else if (addr2.type == MirType.MIR_T_D)
                    func = &fn.fn.ddiv;
                break;
            case TokenKind.Mod:
                func = &fn.fn.mod;
                break;
            default:
                break;
            }

            if (func is null)
                hpy_erro("Operador binario inválido.");

            func(rR, rA, rB);
            store(addr1, rR);
            return addr1.var;

        case Instruction.Chamada:
            CallExpr call = cast(CallExpr) node.a;
            string name = call.name;

            MirFnValue func2 = functions[name];
            MirItem proto = func2.proto;
            MirItem callee = func2.importItem !is null ? func2.importItem : func2.fn.item();

            // carrega cada argumento da memória antes de passar
            MirOp[] args;
            foreach (argName; call.args)
            {
                MirVarValue* av = localGet(argName);
                args ~= load(*av);
            }

            MirVarValue* retVar = localGet(tryGetVarName(node.b));
            MirType retRegType = getRegType(retVar.type);
            MirOp rRet = fn.fn.newReg(temp("call_ret_"), retRegType);
            fn.fn.call(mirRef(ctx.ctx(), proto), mirRef(ctx.ctx(), callee), [
                    rRet
                ], args);
            store(*retVar, rRet);
            return retVar.var;

        case Instruction.Conv:
            MirType de = hToM(node.type);
            MirType para = hToM(node.to);

            MirVarValue var1 = *localGet(tryGetVarName(node.a));
            MirVarValue var2 = *localGet(tryGetVarName(node.b));

            MirOp rSrc = load(var1);

            // casos que precisam de passo intermediário
            if (de == MirType.MIR_T_F && para == MirType.MIR_T_I32)
            {
                auto rTmp = fn.fn.newReg(temp("conv_"), MirType.MIR_T_I64);
                fn.fn.f2i(rTmp, rSrc);
                store(var2, rTmp);
                return var2.var;
            }
            if (de == MirType.MIR_T_D && para == MirType.MIR_T_I32)
            {
                auto rTmp = fn.fn.newReg(temp("conv_"), MirType.MIR_T_I64);
                fn.fn.d2i(rTmp, rSrc);
                store(var2, rTmp);
                return var2.var;
            }
            if (de == MirType.MIR_T_I32 && para == MirType.MIR_T_F)
            {
                auto rTmp = fn.fn.newReg(temp("conv_"), MirType.MIR_T_I64);
                fn.fn.ext32(rTmp, rSrc);
                auto rDst = fn.fn.newReg(temp("conv_"), MirType.MIR_T_F);
                fn.fn.i2f(rDst, rTmp);
                store(var2, rDst);
                return var2.var;
            }
            if (de == MirType.MIR_T_I32 && para == MirType.MIR_T_D)
            {
                auto rTmp = fn.fn.newReg(temp("conv_"), MirType.MIR_T_I64);
                fn.fn.ext32(rTmp, rSrc);
                auto rDst = fn.fn.newReg(temp("conv_"), MirType.MIR_T_D);
                fn.fn.i2d(rDst, rTmp);
                store(var2, rDst);
                return var2.var;
            }

            // extensões e truncamentos: calcula em temp e guarda
            MirOp rDst2 = fn.fn.newReg(temp("conv_"), getRegType(para));

            if (de == MirType.MIR_T_I32 && para == MirType.MIR_T_I64)
                fn.fn.ext32(rDst2, rSrc);
            else if (de == MirType.MIR_T_I8 && (para == MirType.MIR_T_I32 || para == MirType
                    .MIR_T_I64))
                fn.fn.ext8(rDst2, rSrc);
            else if (de == MirType.MIR_T_I16 && (para == MirType.MIR_T_I32 || para == MirType
                    .MIR_T_I64))
                fn.fn.ext16(rDst2, rSrc);
            else if (de == MirType.MIR_T_U8 && (para == MirType.MIR_T_U32 || para == MirType
                    .MIR_T_U64))
                fn.fn.uext8(rDst2, rSrc);
            else if (de == MirType.MIR_T_U16 && (para == MirType.MIR_T_U32 || para == MirType
                    .MIR_T_U64))
                fn.fn.uext16(rDst2, rSrc);
            else if (de == MirType.MIR_T_U32 && para == MirType.MIR_T_U64)
                fn.fn.uext32(rDst2, rSrc);
            else if (de == MirType.MIR_T_F && para == MirType.MIR_T_D)
                fn.fn.f2d(rDst2, rSrc);
            else if (de == MirType.MIR_T_D && para == MirType.MIR_T_F)
                fn.fn.d2f(rDst2, rSrc);
            else if (de == MirType.MIR_T_F && para == MirType.MIR_T_I64)
                fn.fn.f2i(rDst2, rSrc);
            else if (de == MirType.MIR_T_D && para == MirType.MIR_T_I64)
                fn.fn.d2i(rDst2, rSrc);
            else if (de == MirType.MIR_T_I64 && para == MirType.MIR_T_F)
                fn.fn.i2f(rDst2, rSrc);
            else if (de == MirType.MIR_T_I64 && para == MirType.MIR_T_D)
                fn.fn.i2d(rDst2, rSrc);
            else
                fn.fn.mov(rDst2, rSrc); // truncamento ou reinterpret

            store(var2, rDst2);
            return var2.var;

        case Instruction.Compare:
            MirVarValue cx = *localGet(tryGetVarName(node.a));
            MirVarValue cy = *localGet(tryGetVarName(node.b));
            MirVarValue cz = *localGet(tryGetVarName(node.c));

            MirType ctype = hToM(node.type);
            bool isUnsigned = ctype == MirType.MIR_T_U8 || ctype == MirType.MIR_T_U16 ||
                ctype == MirType.MIR_T_U32 || ctype == MirType.MIR_T_U64;

            MirOp rX = load(cx);
            MirOp rY = load(cy);
            MirOp rZ = fn.fn.newReg(temp("cmp_"), MirType.MIR_T_I64);

            switch (node.op)
            {
            case TokenKind.EEquals:
                fn.fn.eq(rZ, rX, rY);
                break;
            case TokenKind.NEquals:
                fn.fn.ne(rZ, rX, rY);
                break;
            case TokenKind.LEquals:
                if (isUnsigned)
                    fn.fn.ule(rZ, rX, rY);
                else
                    fn.fn.le(rZ, rX, rY);
                break;
            case TokenKind.GEquals:
                if (isUnsigned)
                    fn.fn.uge(rZ, rX, rY);
                else
                    fn.fn.ge(rZ, rX, rY);
                break;
            case TokenKind.LThan:
                if (isUnsigned)
                    fn.fn.ult(rZ, rX, rY);
                else
                    fn.fn.lt(rZ, rX, rY);
                break;
            case TokenKind.GThan:
                if (isUnsigned)
                    fn.fn.ugt(rZ, rX, rY);
                else
                    fn.fn.gt(rZ, rX, rY);
                break;
            default:
                hpy_erro(format("Operador de comparação inválido: %s", node.op));
            }
            store(cz, rZ);
            return cz.var;

        case Instruction.Saltez:
        case Instruction.Saltenz:
            bool isNz = node.kind == Instruction.Saltenz;
            MirVarValue cond = *localGet(tryGetVarName(node.a));
            MirOp rCond = load(cond);

            MirOp labelTrue = fn.labels[node.d];
            MirOp labelFalse = fn.labels[node.e];

            if (isNz)
                fn.fn.bt(labelTrue, rCond);
            else
                fn.fn.bf(labelTrue, rCond);
            fn.fn.jmp(labelFalse);
            return MirOp.init;

        case Instruction.Salte:
            fn.fn.jmp(fn.labels[node.d]);
            return MirOp.init;

        case Instruction.Ref:
            // $b = &$a  — b recebe o ponteiro de stack de a
            MirVarValue ra = *localGet(tryGetVarName(node.a));
            MirVarValue rb = *localGet(tryGetVarName(node.b));
            // b.var é um ponteiro de stack — guarda o endereço de a nele
            fn.fn.mov(fn.fn.mem(MirType.MIR_T_I64, rb.var), ra.var);
            return MirOp.init;

        case Instruction.Deref:
            // $b = *$a  — lê o ponteiro guardado em a, depois desreferencia
            MirVarValue da = *localGet(tryGetVarName(node.a));
            MirVarValue db = *localGet(tryGetVarName(node.b));
            // carrega o ponteiro que está na memória de a
            auto rPtr = fn.fn.newReg(temp("deref_ptr_"), MirType.MIR_T_I64);
            fn.fn.mov(rPtr, fn.fn.mem(MirType.MIR_T_I64, da.var));
            // lê o valor apontado e guarda na memória de b
            MirType dbt = db.type;
            MirType dbrt = getRegType(dbt);
            auto rVal = fn.fn.newReg(temp("deref_val_"), dbrt);
            fn.fn.mov(rVal, fn.fn.mem(dbt, rPtr));
            store(db, rVal);
            return db.var;

        case Instruction.Escreva:
            // *$a = $b  — a contém um ponteiro (guardado na stack), b é o valor
            MirVarValue ea = *localGet(tryGetVarName(node.a));
            MirVarValue eb = *localGet(tryGetVarName(node.b));
            // carrega o ponteiro de destino
            auto rDstPtr = fn.fn.newReg(temp("escreva_ptr_"), MirType.MIR_T_I64);
            fn.fn.mov(rDstPtr, fn.fn.mem(MirType.MIR_T_I64, ea.var));
            // carrega o valor a escrever
            MirOp rSrcVal = load(eb);
            fn.fn.mov(fn.fn.mem(eb.type, rDstPtr), rSrcVal);
            return MirOp.init;

        case Instruction.Alocan:
            string varName = tryGetVarName(node.a);
            ulong total = node.f * node.type.getSize();

            // cria um novo reg para o array e sobrescreve a entrada no mapa
            MirOp rArr = fn.fn.newReg(temp(), MirType.MIR_T_I64);
            fn.fn.alloca(rArr, fn.fn.imm(total));
            // atualiza locals para que varName aponte para o novo slot
            localSet(varName, MirVarValue(rArr, MirType.MIR_T_I64, false));
            return rArr;

        default:
            return MirOp.init;
        }
    }

    MirOp compileFnDecl(FuncDecl node)
    {
        string name = node.name;
        const(char)* cname = cStr(name);
        MirType type = hToM(node.type);
        MirVar[] params;
        MirVarValue[string] locals;

        for (ulong i; i < node.args.length; i++)
        {
            FuncArg arg = node.args[i];
            MirType atype = hToM(arg.type);
            params ~= MIR_var(cStr(arg.name), atype, arg.type.getSize());
            locals[arg.name] = MirVarValue(MirOp.init, atype, false);
        }

        MirItem proto = node.isVariadic
            ? mod.newVarArgProto(cStr(name ~ "_proto"), [type], params) : mod.newProto(
                cStr(name ~ "_proto"), [type], params);

        if (node.isExtern)
        {
            MirItem importItem = mod.import_(cname);
            ctx.loadExternal(cname, resolver(cname));
            functions[name] = MirFnValue(name, proto, null, locals, null, null, importItem);
            return MirOp.init;
        }

        MirFunc fun = mod.newFunc(cname, [type], params);
        for (ulong i; i < node.args.length; i++)
        {
            FuncArg arg = node.args[i];
            locals[arg.name].var = fun.reg(cStr(arg.name));
        }

        MirFnValue func = MirFnValue(name, proto, fun, locals, null);
        functions[name] = func;

        MirFnValue* oldFn = fn;
        fn = &functions[name];

        MirOp entryLabel = fn.fn.newLabel();
        fn.fn.appendLabel(entryLabel);

        // processa as labels primeiro
        for (ulong i; i < node.body.length; i++)
            if (node.body[i].kind == NodeKind.LabelStmt)
            {
                LabelStmt label = cast(LabelStmt) node.body[i];
                fn.labels[label.name] = fn.fn.newLabel();
            }

        for (ulong i; i < node.body.length; i++)
            compile(node.body[i]);

        fn.fn.finish();
        fn = oldFn;
        return MirOp.init;
    }

    MirType getRegType(MirType type)
    {
        if (type == MirType.MIR_T_F)
            return MirType.MIR_T_F;
        if (type == MirType.MIR_T_D)
            return MirType.MIR_T_D;
        return MirType.MIR_T_I64;
    }

    MirType hToM(HType type)
    {
        if (type.kind == HTypeKind.Builtin)
        {
            HTypeBuiltin builtin = cast(HTypeBuiltin) type;
            final switch (builtin.base)
            {
            case HTBase.Void:
            case HTBase.I1:
                return MirType.MIR_T_I32;
            case HTBase.I8:
                return MirType.MIR_T_I8;
            case HTBase.U8:
                return MirType.MIR_T_U8;
            case HTBase.I16:
                return MirType.MIR_T_I16;
            case HTBase.U16:
                return MirType.MIR_T_U16;
            case HTBase.I32:
                return MirType.MIR_T_I32;
            case HTBase.U32:
                return MirType.MIR_T_U32;
            case HTBase.I64:
                return MirType.MIR_T_I64;
            case HTBase.U64:
                return MirType.MIR_T_U64;
            case HTBase.F32:
                return MirType.MIR_T_F;
            case HTBase.F64:
                return MirType.MIR_T_D;
            }
        }
        return MirType.MIR_T_I64;
    }

public:
    this()
    {
        this.ctx = new MirContext();
        this.mod = ctx.newModule("main");
    }

    void compile(Program p)
    {
        compile(cast(Node) p);
    }

    int run(bool dump = false, int opt = 2, bool db, StopWatch sw)
    {
        if (dump)
            ctx.dump(stdout);

        mod.finish();
        ctx.load(mod);

        MirJit jit = ctx.jit();
        jit.init();
        jit.setOptLevel(opt);

        ctx.link(null, &resolver);

        if (dump)
        {
            jit.setDebugFile(stderr);
            jit.setDebugLevel(0);
        }

        // compila as funções antes
        foreach (name, ref fnVal; functions)
        {
            if (fnVal.fn is null) continue; // externa, pula
            jit.compileRaw(fnVal.fn);
        }

        alias Main = extern (C) int function();
        Main func = jit.compile!Main(functions["main"].fn);
        checkpoint(db, sw, "jit");

        int code = func();
        checkpoint(db, sw, "main func called");

        jit.finish();
        ctx.finish();

        checkpoint(db, sw, "finish");
        return code;
    }
}
