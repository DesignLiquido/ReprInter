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
            char escape = str[offset];
            switch (escape)
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

void main()
{
    string folder = "exemplos";

    string commandComp = "./harpy %s --aot";
    string commandExec = "./%s";
    string commandRm = "rm -f %s";
    string testResult = "TEST %s - %s";
    ulong sucesso, erros, ignorados;

    DirEntry[] dir = dirEntries(folder, SpanMode.depth).filter!(x => x.name.endsWith(".hp")).array;

    foreach (DirEntry key; dir)
    {
        string filename = key.name();
        string outputFile = filename[0 .. $ - 3];

        alias Exec = Tuple!(int, "status", string, "output");

        Exec comp = executeShell(format(commandComp, filename));

        if (comp.status != 0)
        {
            writefln(testResult, filename, "ERRO");
            writeln(comp.output);
            continue;
        }

        Exec result = executeShell(format(commandExec, outputFile));

        int code = result.status;
        string output = result.output;

        File content = File(filename, "r");
        string firstLine = content.byLine().front.idup;
        bool fromCode, fromOutput;
        bool ok = true;
        string err;

        if (firstLine[0 .. 3] == "//#")
            fromCode = true;
        else if (firstLine[0 .. 3] == "//!")
            fromOutput = true;

        if (fromCode || fromOutput)
            firstLine = firstLine[4 .. $];

        if (fromCode)
        {
            int fileCode = to!int(firstLine);
            if (fileCode != code)
            {
                err = format("Código esperado '%d', recebido '%d'.", fileCode, code);
                ok = false;
            }
        }

        if (fromOutput)
        {
            firstLine = escape(firstLine);
            if (output != firstLine)
            {
                err = format("Saída esperada '%s', recebido '%s'.", firstLine, output);
                ok = true;
            }
        }

        if (!ok)
        {
            writeln(format(testResult, filename, "ERRO"));
            writeln(err);
            erros++;
        }
        else if (ok && (fromCode || fromOutput))
        {
            writefln(format(testResult, filename, "SUCESSO"));
            sucesso++;
        }

        if (!fromCode && !fromOutput)
        {
            writefln("Ignorando arquivo: %s", filename);
            ignorados++;
        }

        executeShell(format(commandRm, outputFile));
    }

    writeln();
    writefln("SUCESSOS: %d\nERROS: %d\nIGNORADOS: %d\nTOTAL: %d", 
        sucesso, erros, ignorados, sucesso + erros + ignorados);
}
