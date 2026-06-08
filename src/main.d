module main;

import core.stdc.stdlib : exit;

import std.datetime.stopwatch;
import std.process;
import std.exception;
import std.format;
import std.getopt;
import std.stdio;
import std.file;
import std.path;

import backend.qbe.codegen;
import backend.jit.mir;
import backend.jit.mir_api;
import backend.jit.codegen;

import type_registry;
import lexer, token;
import parser, ast;
import context;
import errors;
import htype;
import utils;

void verificar_erros(Diagnostics d)
{
    bool err;
    if (d.hasErrors())
        err = true;
    d.report();
    import core.stdc.stdlib : exit;

    if (err)
        exit(1);
}

long last = 0;

void checkpoint(bool time, StopWatch sw, string name)
{
    if (!time)
        return;
    auto now = sw.peek.total!"usecs";
    writeln(name, ": ", now - last);
    last = now;
}

void printDebugTime(StopWatch sw)
{
    sw.stop();
    writeln(sw.peek.total!"usecs", " us");
}

void main(string[] args)
{
    hpy_validar(args.length > 1, "Esperado ao menos um argumento.");

    bool versao, jit, aot, dTime;
    string output = "";

    try
        getopt(args,
            "v|versao", &versao,
            "J|jit", &jit,
            "A|aot", &aot,
            "s|saida", &output,
            "T|tempo", &dTime,
        );

    catch (GetOptException e)
    {
        writefln("Flag invalida: %s\n", e.msg);
        return;
    }

    if (versao)
    {
        // TODO
        return;
    }

    string filename = args[1];

    if (filename.length < 4)
        hpy_erro(format("Arquivo inválido: %s", filename));

    if (extension(filename) != ".hp")
        hpy_erro(format("Extensao de arquivo inválida: %s", filename));

    if (!exists(filename))
        hpy_erro(format("Arquivo não encontrado: %s", filename));

    if (!isFile(filename))
        hpy_erro(format("Isso não é um arquivo: %s", filename));

    StopWatch sw = StopWatch(AutoStart.yes);

    string source = readText(filename);
    checkpoint(dTime, sw, "read");
    Diagnostics diag = new Diagnostics;

    Lexer lexer = new Lexer(source, filename, diag);
    Token[] tokens = lexer.tokenizer();
    checkpoint(dTime, sw, "lexer");
    verificar_erros(diag);

    // foreach (ref Token tk; tokens)
    //     tk.print();

    TypeRegistry registry = new TypeRegistry();
    Context context = new Context(diag);

    Parser parser = new Parser(tokens, diag, registry, context);
    Program program = parser.parse();
    checkpoint(dTime, sw, "parser");
    verificar_erros(diag);
    
    // debugNode(program);

    if (output == "")
        output = filename[0 .. $ - 3];

    if (aot)
    {
        QBECodeGen qbe = new QBECodeGen(registry);
        qbe.compile(program);
        checkpoint(dTime, sw, "qbe");
        string ssa = output ~ ".ssa";
        string s = output ~ ".s";
        qbe.save(ssa);

        int code_qbe = executeShell(format("qbe %s -o %s", ssa, s)).status;
        hpy_validar(code_qbe == 0, "Erro ao compilar com o qbe.");

        int code_cc = executeShell(format("cc %s -O%d -o %s", s, 0, output)).status;
        hpy_validar(code_cc == 0, "Erro ao compilar com o cc.");

        executeShell(format("rm %s %s", ssa, s));
        if (dTime)
            printDebugTime(sw);
        return;
    }
    else if (jit)
    {
        writeln("O JIT está sendo reescrito.");
        return;
    }

    hpy_erro("Escolha um backend pra execução, seja (-A|--aot) ou (-J|--jit)");
}
