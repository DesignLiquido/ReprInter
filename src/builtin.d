module builtin;

// registra funções builtin constantes e outras coisas
// além do mais tem um papel super importante :)

import std.stdio, std.format;
import frontend.type, middle.semantic_analyzer : Symbol;
import frontend.parser.ast;
import backend.codegen : CodeGen;
import backend.harpyvm : HarpyCG, HarpyVM, Instruction, Value, HapyType = Type, OpCode;

alias BuiltinFunctionSignature = void function(CodeGen, HarpyCG, CallExpr, HarpyVM);

struct BuiltinFunction
{
    // regra de nome, sempre inicializa com '@'
    // as informações serão propagadas no analisador semantico e no codegen
    // crie uma vez, use sempre
    string nome;
    Type retorno;
    Type[] args;
    BuiltinFunctionSignature callback;
}

struct BuiltinConstant
{
    // regra de nome, sempre inicializa com '@'
    string nome;
    Type tipo;
    Node valor;
}

struct Builtin
{
    BuiltinFunction[string] funcoes;
    // constantes, ...
}

// Funções {{

private void escreva(CodeGen cg, HarpyCG hcg, CallExpr node, HarpyVM engine)
{
    foreach (arg; node.args)
    {
        cg.generateNode(arg);
        hcg.emit(Instruction(OpCode.PRINT));
    }
}

private void duplicar(CodeGen cg, HarpyCG hcg, CallExpr node, HarpyVM engine)
{
    cg.generateNode(node.args[0]);
    hcg.emit(Instruction(OpCode.DUP));
}

private void tamanhoVetor(CodeGen cg, HarpyCG hcg, CallExpr node, HarpyVM engine)
{
    cg.generateNode(node.args[0]);
    hcg.emit(Instruction(OpCode.ARRL));
}

private void tamanhoTexto(CodeGen cg, HarpyCG hcg, CallExpr node, HarpyVM engine)
{
    cg.generateNode(node.args[0]);
    hcg.emit(Instruction(OpCode.STRL));
}

// texto para decimal
private void tpd(CodeGen cg, HarpyCG hcg, CallExpr node, HarpyVM engine)
{
    cg.generateNode(node.args[0]);
    hcg.emit(Instruction(OpCode.STOF));
}

// int para decimal
private void ipd(CodeGen cg, HarpyCG hcg, CallExpr node, HarpyVM engine)
{
    cg.generateNode(node.args[0]);
    hcg.emit(Instruction(OpCode.ITOF));
}

private void tipoParaTexto(CodeGen cg, HarpyCG hcg, CallExpr node, HarpyVM engine)
{
    cg.generateNode(node.args[0]);
    hcg.emit(Instruction(OpCode.TRAW));
}

private void vetorPop(CodeGen cg, HarpyCG hcg, CallExpr node, HarpyVM engine)
{
    cg.generateNode(node.args[0]);
    hcg.emit(Instruction(OpCode.ARRPP));
}

private void sair(CodeGen cg, HarpyCG hcg, CallExpr node, HarpyVM engine)
{
    cg.generateNode(node.args[0]);
    hcg.emit(Instruction(OpCode.EXIT));
}

private void input(CodeGen cg, HarpyCG hcg, CallExpr node, HarpyVM engine)
{
    hcg.emit(Instruction(OpCode.INPUT));
}

// }} Funções FIM

private void registrarFuncoes(ref Builtin builtin)
{
    builtin.funcoes["@escreva"] = BuiltinFunction(
        "@escreva",
        Type(Types.Void, BaseType.Void),
        [Type(Types.Undefined, BaseType.Any, true)],
        &escreva
    );

    builtin.funcoes["@entrada"] = BuiltinFunction(
        "@entrada",
        Type(Types.Literal, BaseType.String),
        [],
        &input
    );

    builtin.funcoes["@duplicar"] = BuiltinFunction(
        "@duplicar",
        Type(Types.Literal, BaseType.Any),
        [Type(Types.Literal, BaseType.Any)],
        &duplicar
    );

    builtin.funcoes["@tamanho_vetor"] = BuiltinFunction(
        "@tamanho_vetor",
        Type(Types.Literal, BaseType.Int),
        [Type(Types.Array, BaseType.Any)],
        &tamanhoVetor
    );

    builtin.funcoes["@tamanho_texto"] = BuiltinFunction(
        "@tamanho_texto",
        Type(Types.Literal, BaseType.Int),
        [Type(Types.Literal, BaseType.String)],
        &tamanhoTexto
    );

    builtin.funcoes["@tpd"] = BuiltinFunction(
        "@tpd",
        Type(Types.Literal, BaseType.Int),
        [Type(Types.Literal, BaseType.String)],
        &tpd
    );

    builtin.funcoes["@ipd"] = BuiltinFunction(
        "@ipd",
        Type(Types.Literal, BaseType.Double),
        [Type(Types.Literal, BaseType.Int)],
        &ipd
    );

    builtin.funcoes["@tipo"] = BuiltinFunction(
        "@tipo",
        Type(Types.Literal, BaseType.String),
        [Type(Types.Literal, BaseType.Any)],
        &tipoParaTexto
    );

    builtin.funcoes["@vetor_pop"] = BuiltinFunction(
        "@vetor_pop",
        Type(Types.Literal, BaseType.Any),
        [Type(Types.Array, BaseType.Any)],
        &vetorPop
    );

    builtin.funcoes["@sair"] = BuiltinFunction(
        "@sair",
        Type(Types.Void, BaseType.Void),
        [Type(Types.Literal, BaseType.Int)],
        &sair
    );
}

Builtin registrarBuiltin()
{
    Builtin builtin;
    registrarFuncoes(builtin);
    return builtin;
}
