module lib.d.harpy_valor;

alias Tipo = HarpyTipo;
alias Valor = HarpyValor;

enum HarpyTipo : string
{
    Inteiro = "inteiro",
    Texto = "texto",
    Logico = "logico",
    Decimal = "decimal",
    Vazio = "vazio",
    Estrutura = "estrutura",
    Enum = "enum",
    Variadic = "...",
}

struct HarpyValor
{
    string valor; // exemplo: x 
    HarpyTipo tipo;
}
