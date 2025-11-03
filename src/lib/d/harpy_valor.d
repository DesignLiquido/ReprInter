module lib.d.harpy_valor;

alias Tipo = HarpyTipo;
alias Valor = HarpyValor;

enum HarpyTipo : string
{
    Inteiro = "inteiro",
    Int = "int",
    I64 = "i64",
    Vazio = "vazio",
}

struct HarpyValor
{
    string valor; // exemplo: x 
    HarpyTipo tipo;
}
