module lib.d.harpy_funcao;

import std.stdio, std.conv, std.format;
import lib.d.harpy_contador, lib.d.harpy_valor, lib.d.harpy_bloco;

class HarpyFuncao
{
private:
    string nome;
    HarpyTipo tipoDeRetorno;
    HarpyValor[] params;
    HarpyBloco bloco;
public:
    this(string nome, HarpyTipo tipo, HarpyValor[] params = [])
    {
        this.nome = nome;
        this.tipoDeRetorno = tipo;
        this.params = params;
    }

    Valor getArg(ulong indice = 0)
    {
        if (indice > (cast(ulong) params.length - 1))
            throw new Exception("O indice é maior do que o permitido.");
        return params[indice];
    }

    void definirBloco(HarpyBloco bloco)
    {
        this.bloco = bloco;
    }

    string gerar(bool isExtern = false)
    {
        string codigo = format("declarar %s (", nome);
        for (long i; i < params.length; i++)
        {
            if (params[i].tipo == HarpyTipo.Variadic)
            {
                codigo ~= "...";
                break;
            }
            codigo ~= params[i].valor;
            codigo ~= " ";
            codigo ~= params[i].tipo;
            if (!((i + 1) >= params.length))
                codigo ~= ", ";
        }
        codigo ~= ") ";
        codigo ~= tipoDeRetorno;
        if (!isExtern)
            codigo ~= bloco.gerar();
        else
            codigo ~= ";";
        return codigo;
    }
}
