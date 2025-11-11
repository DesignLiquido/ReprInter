module lib.d.harpy_modulo;

import std.stdio, std.conv, std.array, std.algorithm, std.format;
import lib.d.harpy_funcao, lib.d.harpy_externo;

class HarpyModulo
{
private:
    string nome;
    HarpyFuncao[] funcoes;
    HarpyExterno externo = null;
public:
    this(string nome = "main.rp")
    {
        this.nome = nome;
    }

    void addFuncao(HarpyFuncao func)
    {
        this.funcoes ~= func;
    }

    void definirExterno(HarpyExterno externo)
    {
        this.externo = externo;
    }

    string gerar()
    {
        string codigo = externo is null ? "" : externo.gerar();
        codigo ~= funcoes.map!(f => f.gerar()).array.join("\n");
        return codigo;
    }
}
