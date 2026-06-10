module tests.unit;
import std.format;
import std.stdio;
import std.file;
import std.algorithm;
import std.array;
import std.process;
import std.typecons;
import std.range;
import std.conv;

string escape(string str)
{
    ulong offset;
    string buffer;
    while (offset < str.length)
    {
        char ch = str[offset++];
        if (ch == '\\' && offset < str.length)
        {
            char esc = str[offset];
            switch (esc)
            {
            case 'n':
                buffer ~= '\n';
                offset++;
                continue;
            default:
                break;
            }
        }
        buffer ~= [ch];
    }
    return buffer;
}

enum Backend { AOT, JIT }

struct TestResult
{
    string filename;
    Backend backend;
    bool ok;
    string err;
    bool ignored;
}

TestResult runTest(string filename, Backend backend)
{
    alias Exec = Tuple!(int, "status", string, "output");
    TestResult res;
    res.filename = filename;
    res.backend  = backend;

    File content = File(filename, "r");
    string firstLine = content.byLine().front.idup;
    content.close();

    bool fromCode   = firstLine.length > 3 && firstLine[0 .. 3] == "//#";
    bool fromOutput = firstLine.length > 3 && firstLine[0 .. 3] == "//!";

    if (!fromCode && !fromOutput)
    {
        res.ignored = true;
        return res;
    }

    firstLine = firstLine[4 .. $];

    string output;
    int    code;

    if (backend == Backend.AOT)
    {
        string outputFile = filename[0 .. $ - 3];
        Exec comp = executeShell(format("./harpy %s --aot", filename));
        if (comp.status != 0)
        {
            res.ok  = false;
            res.err = "Falha na compilação AOT:\n" ~ comp.output;
            return res;
        }
        Exec run = executeShell(format("./%s", outputFile));
        code   = run.status;
        output = run.output;
        executeShell(format("rm -f %s", outputFile));
    }
    else // JIT
    {
        Exec run = executeShell(format("./harpy %s --jit", filename));
        code   = run.status;
        output = run.output;
        // remove aviso do JIT da saída
        output = output.replace("AVISO: O JIT está sendo reescrito, por isso alguns exemplos podem dar erro.\n", "");
    }

    res.ok = true;

    if (fromCode)
    {
        int expected = to!int(firstLine);
        if (expected != code)
        {
            res.ok  = false;
            res.err = format("Código esperado '%d', recebido '%d'.", expected, code);
        }
    }
    else if (fromOutput)
    {
        string expected = escape(firstLine);
        if (output != expected)
        {
            res.ok  = false;
            res.err = format("Saída esperada '%s', recebida '%s'.", expected, output);
        }
    }

    return res;
}

void main()
{
    string folder = "exemplos";
    ulong sucesso, erros, ignorados;

    DirEntry[] dir = dirEntries(folder, SpanMode.depth)
        .filter!(x => x.name.endsWith(".hp"))
        .array
        .sort!((a, b) => a.name < b.name)
        .array;

    writeln("=== AOT ===");
    foreach (DirEntry key; dir)
    {
        TestResult res = runTest(key.name, Backend.AOT);
        if (res.ignored)
        {
            writefln("  IGNORADO  %s", res.filename);
            ignorados++;
        }
        else if (res.ok)
        {
            writefln("  SUCESSO   %s", res.filename);
            sucesso++;
        }
        else
        {
            writefln("  ERRO      %s", res.filename);
            writeln("            ", res.err);
            erros++;
        }
    }

    writeln();
    writeln("=== JIT ===");
    foreach (DirEntry key; dir)
    {
        TestResult res = runTest(key.name, Backend.JIT);
        if (res.ignored)
        {
            writefln("  IGNORADO  %s", res.filename);
            ignorados++;
        }
        else if (res.ok)
        {
            writefln("  SUCESSO   %s", res.filename);
            sucesso++;
        }
        else
        {
            writefln("  ERRO      %s", res.filename);
            writeln("            ", res.err);
            erros++;
        }
    }

    writeln();
    writefln("SUCESSOS:  %d", sucesso);
    writefln("ERROS:     %d", erros);
    writefln("IGNORADOS: %d", ignorados);
    writefln("TOTAL:     %d", sucesso + erros + ignorados);
}
