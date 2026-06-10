//                            .''.
//                           (~~~~)
//                             ||
//                           __||__
//                          /______\
//                            |  |' _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _
//                            |  |'|o| - - - - - - - - - - - - - - - - - - - - - - - - -||
//                            |  |'| |                                                  ||
//                            |  |'| |                      . ' .                       ||
//                            |  |'| |                  . '       ' .                   ||
//                            |  |'| |              . '    .-'"'-.    ' .               ||
//                            |  |'| |          . '      ,"       ".      ' .           ||
//                            |  |'| |      . '        /:   x0x0x   :\        ' .       ||
//                            |  |'| |  . '            ;  . x0x0x    ;            ' .   ||
//                            |  |'| |    ' .          \: ..x0x0x   :/          . '     ||
//                            |  |'| |        ' .        `. . .    ,/       . '         ||
//                            |  |'| |            ' .      `-.,,.-'     . '             ||
//                            |  |'| |                ' .           . '                 ||
//                            |  |'| |                    ' .   . '                     ||
//                            |  |'| |                        '                         ||
//                            |  |'|o|-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_-_||
//                            |  |'
//                            |  |'
//                            |  |' 
//                            |  |'
//                            '~~'

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

const string VERSAO = "1.0.0";

void verificar_erros(Diagnostics d)
{
    d.report();
    if (d.hasErrors())
        exit(1);
}

long last = 0;

void checkpoint(bool time, StopWatch sw, string name)
{
    if (!time)
        return;
    auto now = sw.peek.total!"usecs";
    writeln("[DEBUG TIME] ", name, ": ", now - last, "µs");
    last = now;
}

void printDebugTime(StopWatch sw)
{
    sw.stop();
    writeln("[DEBUG TIME] TOTAL: ", sw.peek.total!"usecs", " µs");
}

int main(string[] args)
{
    hpy_validar(args.length > 1, "Esperado ao menos um argumento.");

    bool versao, jit, aot, dTime, sAst, sAsm, sSsa, sMir;
    int opt = 0;
    string output = "";

    try
        getopt(args,
            "v|versao", &versao,
            "J|jit", &jit,
            "A|aot", &aot,
            "s|saida", &output,
            "T|tempo", &dTime,
            "ast", &sAst,
            "asm", &sAsm,
            "ssa", &sSsa,
            "mir", &sMir,
        );

    catch (GetOptException e)
    {
        writefln("Flag invalida: %s\n", e.msg);
        return 1;
    }

    if (versao)
    {
        // TODO
        return 0;
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

    TypeRegistry registry = new TypeRegistry();
    Context context = new Context(diag);

    Parser parser = new Parser(tokens, diag, registry, context);
    Program program = parser.parse();
    checkpoint(dTime, sw, "parser");
    verificar_erros(diag);

    if (sAst)
        debugNode(program);

    if (output == "")
        output = filename[0 .. $ - 3];

    if (aot)
    {
        QBECodeGen qbe = new QBECodeGen();
        qbe.compile(program);
        checkpoint(dTime, sw, "qbe");
        
        string ssa = output ~ ".ssa";
        string s = output ~ ".s";
        qbe.save(ssa);

        int code_qbe = executeShell(format("qbe %s -o %s", ssa, s)).status;
        hpy_validar(code_qbe == 0, "Erro ao compilar com o qbe.");

        int code_cc = executeShell(format("cc %s -O%d -o %s", s, 0, output)).status;
        hpy_validar(code_cc == 0, "Erro ao compilar com o cc.");

        if (!sAsm)
            executeShell("rm -f " ~ s);

        if (!sSsa)
            executeShell("rm -f " ~ ssa);

        if (dTime)
            printDebugTime(sw);
            
        return 0;
    }
    else if (jit)
    {
        MIRCodeGen mir = new MIRCodeGen();
        
        mir.compile(program);
        checkpoint(dTime, sw, "mir");
        
        int code = mir.run(sMir, opt, dTime, sw);
        if (dTime)
            printDebugTime(sw);

        return code;
    }

    hpy_erro("Escolha um backend pra execução, seja (-A|--aot) ou (-J|--jit)");
    return 1;
}
