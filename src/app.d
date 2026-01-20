module app;

import harpyvm;
import std.stdio, std.file, std.path, std.format;
import core.stdc.stdlib : exit, EXIT_FAILURE, free, malloc;

void erro(string msg)
{
    writefln("Erro: %s", msg);
    exit(EXIT_FAILURE);
}

void main(string[] args) 
{
    if (args.length != 2)
        erro("É esperado um unico arquivo como argumento.");

    string arquivo = args[1];
    if (extension(arquivo) != ".hvm")
        erro(format("O arquivo '%s' deve ser um arquivo harpy válido!", arquivo));
}
