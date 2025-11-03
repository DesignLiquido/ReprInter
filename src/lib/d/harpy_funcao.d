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
        // TODO: Validar
        return params[indice];
    }

    void definirBloco(HarpyBloco bloco)
    {
        this.bloco = bloco;
    }

    string gerar()
    {
        string codigo = format("declarar %s (", nome);
        for (long i; i < params.length; i++)
        {
            codigo ~= params[i].valor;
            codigo ~= " ";
            codigo ~= params[i].tipo;
            if (!((i + 1) >= params.length))
                codigo ~= ", ";
        }
        codigo ~= ") ";
        codigo ~= tipoDeRetorno;
        codigo ~= bloco.gerar();
        return codigo;
    }
}
