# Harpy

**Harpy** é um backend para compiladores e interpretadores com suporte nativo a AOT e JIT. Para utilizá-lo, o compilador-alvo gera IR (Representação Intermediária) inteiramente em português — uma escolha deliberada: o projeto é brasileiro, feito para falantes de língua portuguesa.

## Arquitetura

O backend é composto por dois motores:

- **QBE** — responsável pela compilação AOT (ahead-of-time), gerando código nativo de alta performance.
- **MIR** (vnmakarov/mir) — responsável pela compilação JIT (just-in-time), permitindo execução dinâmica em tempo de execução.

Um IR, dois destinos.

## Pipeline

O Harpy possui um Lexer, um Parser e um único passe de análise estática. Esse passe resolve tudo o que é necessário para a geração de código:

- Determina o tamanho dos tipos primitivos
- Calcula tamanho, alinhamento e offset de cada campo em structs
- Gera um registrador virtual por variável
- Valida existência de variáveis e funções (feito durante o parsing, não após)

A checagem de tipos e escopo acontece durante o parsing para eliminar passagens extras sobre a árvore.

## AST

O resultado do pipeline é uma AST extremamente enxuta. Sem anotações desnecessárias, sem nós descartáveis — apenas o suficiente para alimentar qualquer um dos backends e produzir o resultado final.

## Status

O projeto tem menos de 5 dias de vida. Está em fase inicial — e isso é animador.
