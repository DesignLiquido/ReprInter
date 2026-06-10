module backend.qbe.codegen;

import backend.qbe.qbe_api;
import std.stdio;
import std.conv;
import errors;
import token;
import htype;
import utils;
import ast;

struct QBEVarValue
{
    QBEValue value;
    QBEType type; // tipo original
    bool isParam;
}

class QBECodeGen
{
private:
    // salva o endereço de cada variavel
    string fn;
    QBEVarValue[string][string] map;
    QBEValue[string] functions;
    QBEBuilder builder;
    QBEValue[string] strings;
    
    QBEValue compile(Node node)
    {
        switch (node.kind)
        {
        case NodeKind.Program:
            Program p = cast(Program) node;
            for (uint i; i < p.decls.length; i++)
                compile(p.decls[i]);
            return QBEValue.init;

        case NodeKind.FuncDecl:
            return compileFnDecl(cast(FuncDecl) node);

        case NodeKind.InstructionStmt:
            return compileInstr(cast(InstructionStmt) node);

        case NodeKind.IntLit:
            IntLit lit = cast(IntLit) node;
            return QBEValue.makeConst(lit.val, hToQ(lit.type));

        case NodeKind.DoubleLit:
            DoubleLit lit = cast(DoubleLit) node;
            return QBEValue.makeFloatConst(lit.val);

        case NodeKind.StringLit:
            StringLit lit = cast(StringLit) node;
            if (QBEValue* val = lit.val in strings)
                return *val;
            string n = "_str" ~ to!string(strings.length);
            QBEData data = builder.getModule().addData(n);
            data.addString(lit.val);
            QBEValue val = QBEValue.makeGlobal(n);
            strings[lit.val] = val;
            return val;

        case NodeKind.StructDecl:
            return compileStructDecl(cast(StructDecl) node);

        case NodeKind.LabelStmt:
            LabelStmt label = cast(LabelStmt) node;
            builder.startBlock(label.name);
            for (ulong i; i < label.body.length; i++)
                compile(label.body[i]);
            return QBEValue.makeTemp(label.name);

        default:
            debugNode(node);
            hpy_erro("QBE: Node desconhecido.");
            return QBEValue.init;
        }
    }

    QBEValue compileStructDecl(StructDecl node)
    {
        QBEAggregate t = new QBEAggregate(node.name);
        for (ulong i; i < node.fields.length; i++)
        {
            StructField field = node.fields[i];
            t.addField(hToQ(field.type));
            // testando padding após o campo
            if (field.padding > 0)
                t.addField(QBEType.Byte, field.padding);
        }
        builder.getModule().addType(t);
        return QBEValue.init;
    }

    QBEValue makeLoad(QBEVarValue val)
    {
        if (val.isParam)
            return val.value;
        return builder.load(val.type, val.value);
    }

    string tryGetVarName(Node node)
    {
        hpy_validar(node.kind == NodeKind.IDentifier, "Esperado um nome para a variavel.");
        return (cast(IDentifier) node).val;
    }

    QBEValue compileInstr(InstructionStmt node)
    {
        final switch (node.kind)
        {
        case Instruction.Aloca:
            QBEType type = hToQ(node.type);
            QBEValue alloc = builder.alloc(node.type.getSize(), type);
            string var = tryGetVarName(node.a);
            map[fn][var] = QBEVarValue(alloc, type);
            return alloc;

        case Instruction.Ret:
            string var = tryGetVarName(node.a);
            QBEVarValue addr = map[fn][var];

            builder.ret(makeLoad(addr)); // carrega o valor e retorna
            return addr.value;

        case Instruction.Ime:
            string var = tryGetVarName(node.a);
            QBEVarValue addr = map[fn][var];
            QBEValue value = compile(node.b);

            builder.store(addr.type, value, addr.value);
            return addr.value;

        case Instruction.Setar:
            string estr = tryGetVarName(node.a);
            string fName = tryGetVarName(node.b);
            string val = tryGetVarName(node.c);

            if (node.type.kind != HTypeKind.Struct)
            {
                // TODO: melhorar
                hpy_erro("Setar em um tipo inválido.");
                return QBEValue.init;
            }

            QBEVarValue addr1 = map[fn][estr]; // a variavel alvo
            QBEVarValue addr2 = map[fn][val]; // variavel com o valor destino

            HTypeStruct type = cast(HTypeStruct) node.type;
            StructField* field = fName in type.fields;

            if (field is null)
            {
                hpy_erro("O Campo não existe.");
                return QBEValue.init;
            }

            QBEValue fieldPtr = builder.add(QBEType.Long, addr1.value, QBEValue.makeConst(
                    field.offset));
            builder.store(hToQ(field.type), makeLoad(addr2), fieldPtr);

            return QBEValue.init;

        case Instruction.Obter:
            string estr = tryGetVarName(node.a);
            string fName = tryGetVarName(node.b);
            string val = tryGetVarName(node.c);

            if (node.type.kind != HTypeKind.Struct)
            {
                // TODO: melhorar
                hpy_erro("Obter em um tipo inválido.");
                return QBEValue.init;
            }

            QBEVarValue addr1 = map[fn][estr]; // a variavel alvo
            QBEVarValue addr2 = map[fn][val]; // variavel com o valor destino

            HTypeStruct type = cast(HTypeStruct) node.type;
            StructField* field = fName in type.fields;

            if (field is null)
            {
                hpy_erro("O Campo não existe.");
                return QBEValue.init;
            }

            QBEValue fieldPtr = builder.add(QBEType.Long, addr1.value, QBEValue.makeConst(
                    field.offset));
            QBEValue loaded = builder.load(hToQ(field.type), fieldPtr);
            builder.store(hToQ(field.type), loaded, addr2.value);
            return addr2.value;

        case Instruction.Aritmetica:
            string res = tryGetVarName(node.a);
            string x = tryGetVarName(node.b);
            string y = tryGetVarName(node.c);

            QBEVarValue addr1 = map[fn][res];
            QBEVarValue addr2 = map[fn][x];
            QBEVarValue addr3 = map[fn][y];

            QBEValue lx = makeLoad(addr2);
            QBEValue ly = makeLoad(addr3);

            alias FnOP = QBEValue delegate(QBEType, QBEValue, QBEValue);
            FnOP func = null;

            switch (node.op)
            {
            case TokenKind.Soma:
                func = &builder.add;
                break;
            case TokenKind.Sub:
                func = &builder.sub;
                break;
            case TokenKind.Mul:
                func = &builder.mul;
                break;
            case TokenKind.Div:
                func = &builder.div;
                break;
            case TokenKind.Mod:
                func = &builder.rem;
                break;
            default:
                break;
            }

            if (func is null)
            {
                hpy_erro("Operador binario inválido.");
                return QBEValue.init;
            }

            QBEValue result = func(addr1.type, lx, ly);
            builder.store(addr1.type, result, addr1.value);

            return result;

        case Instruction.Chamada:
            CallExpr call = cast(CallExpr) node.a;
            QBEValue func = functions[call.name];
            QBEValue[] args;
            for (ulong i; i < call.args.length; i++)
                args ~= makeLoad(map[fn][call.args[i]]);
            QBEValue value = builder.call(func.type, func, args);
            QBEValue res = map[fn][tryGetVarName(node.b)].value;
            builder.store(func.type, value, res);
            return res;

        case Instruction.Conv:
            QBEType de = hToQ(node.type);
            QBEType para = hToQ(node.to);

            QBEVarValue var1 = map[fn][tryGetVarName(node.a)]; // origem
            QBEVarValue var2 = map[fn][tryGetVarName(node.b)]; // salvamento

            QBEValue result = builder.cast_(para, de, makeLoad(var1));
            builder.store(para, result, var2.value);

            return var2.value;

        case Instruction.Compare:
            QBEType type = hToQ(node.type);

            QBEVarValue x = map[fn][tryGetVarName(node.a)];
            QBEVarValue y = map[fn][tryGetVarName(node.b)];
            QBEVarValue z = map[fn][tryGetVarName(node.c)];

            QBEValue lx = makeLoad(x);
            QBEValue ly = makeLoad(y);

            string getOp(TokenKind op)
            {
                bool isFloat = node.type.kind == HTypeKind.Builtin &&
                    (
                        (cast(HTypeBuiltin) node.type).base == HTBase.F32 ||
                            (cast(HTypeBuiltin) node.type).base == HTBase.F64
                    );

                bool isUnsigned = node.type.kind == HTypeKind.Builtin &&
                    (
                        (cast(HTypeBuiltin) node.type).base == HTBase.U8 ||
                            (cast(HTypeBuiltin) node.type).base == HTBase.U16 ||
                            (cast(HTypeBuiltin) node.type)
                            .base == HTBase.U32 ||
                            (cast(HTypeBuiltin) node.type).base == HTBase.U64
                    );

                switch (op)
                {
                case TokenKind.EEquals:
                    return "eq";
                case TokenKind.NEquals:
                    return "ne";
                case TokenKind.LEquals:
                    return isFloat ? "le" : (isUnsigned ? "ule" : "sle");
                case TokenKind.GEquals:
                    return isFloat ? "ge" : (isUnsigned ? "uge" : "sge");
                case TokenKind.LThan:
                    return isFloat ? "lt" : (isUnsigned ? "ult" : "slt");
                case TokenKind.GThan:
                    return isFloat ? "gt" : (isUnsigned ? "ugt" : "sgt");
                default:
                    return "<err>";
                }
            }

            builder.store(type, builder.cmp(getOp(node.op), type, lx, ly), z.value);
            return QBEValue.init;

        case Instruction.Saltez:
        case Instruction.Saltenz:
            bool isNz = node.kind == Instruction.Saltenz;
            QBEVarValue cond = map[fn][tryGetVarName(node.a)];
            QBEValue condVal = makeLoad(cond);
            if (isNz)
                builder.jnz(condVal, node.d, node.e);
            else
                builder.jnz(condVal, node.e, node.d);
            return QBEValue.init;

        case Instruction.Salte:
            builder.jmp(node.d);
            return QBEValue.init;

        case Instruction.Ref:
            // ref $a, $b
            // $b = &$a
            QBEVarValue a = map[fn][tryGetVarName(node.a)];
            QBEVarValue b = map[fn][tryGetVarName(node.b)];
            builder.store(QBEType.Long, a.value, b.value);
            return QBEValue.init;

        case Instruction.Deref:
            // deref $a, $b
            // $b = *$a
            QBEVarValue a = map[fn][tryGetVarName(node.a)];
            QBEVarValue b = map[fn][tryGetVarName(node.b)];

            QBEValue ptr = makeLoad(a);
            QBEValue val = builder.load(b.type, ptr);

            builder.store(b.type, val, b.value);
            return QBEValue.init;

        case Instruction.Escreva:
            // escreva $a, $b
            // *$a = $b
            QBEVarValue a = map[fn][tryGetVarName(node.a)];
            QBEVarValue b = map[fn][tryGetVarName(node.b)];
            builder.store(b.type, makeLoad(b), makeLoad(a));
            return QBEValue.init;

        case Instruction.Alocan:
            // alocarn T, $target, $tam

            QBEType type = hToQ(node.type);
            string varName = tryGetVarName(node.a);
            ulong total = node.f * node.type.getSize();

            QBEValue mem = builder.alloc(total, type);
            map[fn][varName] = QBEVarValue(mem, QBEType.Long, true);
            return QBEValue.init;
        }
    }

    QBEValue compileFnDecl(FuncDecl node)
    {
        string name = node.name;
        fn = name;
        map[name] = (QBEVarValue[string]).init;
        QBEType type = hToQ(node.type);
        functions[name] = QBEValue.makeGlobal(name, type);

        if (node.isExtern)
            return QBEValue.init;

        QBEFunction func = builder.startFunction(name, type);
        for (ulong i; i < node.args.length; i++)
        {
            FuncArg arg = node.args[i];
            QBEType atype = hToQ(arg.type);
            func.addParam(hToQ(arg.type), arg.name);
            map[fn][arg.name] = QBEVarValue(QBEValue.makeTemp(arg.name, atype), atype, true);
        }
        builder.startBlock("entry");
        for (ulong i; i < node.body.length; i++)
            compile(node.body[i]);
        return QBEValue.init;
    }

    QBEType hToQ(HType type)
    {
        if (type.kind == HTypeKind.Builtin)
        {
            HTypeBuiltin builtin = cast(HTypeBuiltin) type;
            final switch (builtin.base)
            {
            case HTBase.Void:
                return QBEType.Word; // valor padrao
            case HTBase.I1:
            case HTBase.I8:
            case HTBase.U8:
                return QBEType.Byte;
            case HTBase.I16:
            case HTBase.U16:
                return QBEType.Halfword;
            case HTBase.I32:
            case HTBase.U32:
                return QBEType.Word;
            case HTBase.I64:
            case HTBase.U64:
                return QBEType.Long;
            case HTBase.F32:
                return QBEType.Single;
            case HTBase.F64:
                return QBEType.Double;
            }
        }
        // writeln("Tipo desconhecido.");
        return QBEType.Long;
    }

public:
    this()
    {
        this.builder = new QBEBuilder();
    }

    string compile(Program p)
    {
        compile(cast(Node) p);
        return builder.getModule().toString();
    }

    void save(string file)
    {
        builder.getModule().writeToFile(file);
    }
}
