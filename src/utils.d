module utils;

import core.stdc.stdlib : exit;
import std.exception;
import std.stdio;
import std.format;

void hpy_erro(string message)
{
    writefln("Harpy Erro: %s", message);
    exit(1);
}

void hpy_validar(bool cond, string message)
{
    if (cond)
        return;
    hpy_erro(message);
}
