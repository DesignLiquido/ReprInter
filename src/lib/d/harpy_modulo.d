module lib.d.harpy_modulo;

import std.stdio, std.conv, std.array, std.algorithm, std.format;
import lib.d.harpy_funcao;

class HarpyModulo
{
private:
    string nome;
    HarpyFuncao[] funcoes;
public:
    this(string nome = "main.rp")
    {
        this.nome = nome;
    }

    void addFuncao(HarpyFuncao func)
    {
        this.funcoes ~= func;
    }

    string gerar()
    {
        string codigo = funcoes.map!(f => f.gerar()).array.join("\n");
        return codigo;
    }
}
