module lib.d.harpy_bloco;

import std.stdio, std.conv, std.array, std.format;
import lib.d.harpy_valor, lib.d.harpy_contador;

class HarpyBloco
{
private:
    HarpyContadorTemporario contador;
    string[] instrucoes;

    void emitir(string codigo)
    {
        this.instrucoes ~= codigo;
    }

public:
    this(HarpyContadorTemporario contador)
    {
        this.contador = contador;
    }

    Valor varTmp(Tipo tipo)
    {
        string nome = to!string(contador.proximo());
        emitir(format("alocar $%s %s;", nome, cast(string) tipo));
        return Valor("$" ~ nome, tipo);
    }

    Valor varTmp(Tipo tipo, string valor)
    {
        string nome = to!string(contador.proximo());
        emitir(format("alocar $%s %s = %s", nome, cast(string) tipo, valor));
        return Valor("$" ~ nome, tipo);
    }

    Valor var(string nome, Tipo tipo, string valor)
    {
        emitir(format("alocar %s %s = %s", nome, cast(string) tipo, valor));
        return Valor(nome, tipo);
    }

    string sargs(Valor[] args)
    {
        string sargs;
        for (long i; i < args.length; i++)
        {
            sargs ~= format("%s", args[i].valor);
            if (!((i + 1) >= args.length))
                sargs ~= ", ";
        }
        return sargs;
    }

    Valor call(string fn, Tipo tipo, Valor[] args)
    {
        string sargs = sargs(args);
        return varTmp(tipo, format("%s(%s)", fn, sargs));
    }

    Valor call(string fn, Valor[] args, Valor target)
    {
        string sargs = sargs(args);
        emitir(format("%s = %s(%s)", target.valor, fn, sargs));
        return target;
    }

    Valor add(Tipo tipo, Valor x, Valor y)
    {
        return varTmp(tipo, format("%s + %s", x.valor, y.valor));
    }

    Valor print(Valor valor)
    {
        emitir(format("__nucleo_harpy_escreva(%s)", valor.valor));
        return valor;
    }

    Valor ret(Valor valor)
    {
        emitir(format("retorne %s", valor.valor));
        return valor;
    }

    Valor fim()
    {
        emitir("fim");
        return Valor("\0", Tipo.Vazio);
    }

    string gerar()
    {
        string codigo = " {\n";
        foreach (instr; instrucoes)
            codigo ~= "    " ~ instr ~ "\n";
        codigo ~= "}\n";
        return codigo;
    }
}
