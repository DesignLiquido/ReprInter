module lib.d.harpy_externo;

import std.stdio, std.conv, std.array, std.format;
import lib.d.harpy_valor, lib.d.harpy_contador, lib.d.harpy_funcao;

class HarpyExterno
{
private:
    HarpyFuncao[] funcoes;

public:
    HarpyExterno addFuncao(HarpyFuncao func)
    {
        this.funcoes ~= func;
        return this;
    }

    string gerar()
    {
        string codigo = "externo {\n";
        foreach (HarpyFuncao func; funcoes)
        {
            codigo ~= "\t";
            codigo ~= func.gerar(true);
        }
        codigo ~= "\n}\n\n";
        return codigo;
    }
}
