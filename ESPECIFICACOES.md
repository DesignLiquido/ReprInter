# Especificações do Projeto Harpy

Harpy é um backend para compiladores e interpretadores com uma Representação Intermediária (IR) inteiramente em português. É o primeiro backend desenvolvido no Brasil com essa proposta, com o objetivo de facilitar o aprendizado e a experimentação na nossa língua nativa.

Suporta dois modelos de compilação: **AOT** (*Ahead-of-Time*) via QBE e **JIT** (*Just-in-Time*) via MIR (vnmakarov/mir). Um único IR, dois destinos.

---

## Referências Técnicas

Esta seção explica os conceitos e tecnologias sobre os quais a Harpy é construída.

### AOT — Compilação Antecipada (*Ahead-of-Time*)

Compilação antecipada é o modelo tradicional de compilação: o código-fonte é inteiramente traduzido para código de máquina **antes** da execução. O resultado é um binário independente que pode ser executado diretamente pelo sistema operacional sem nenhuma infraestrutura adicional em tempo de execução.

Vantagens: performance máxima, binário autossuficiente, sem overhead de inicialização.
Desvantagem: a compilação precisa acontecer antes de qualquer execução, o que torna o ciclo de edição mais lento em comparação ao JIT.

Na Harpy, o modo AOT passa pelo seguinte pipeline:

```
.hp → parser → QBECodeGen → .ssa (IR do QBE) → qbe → .s (Assembly) → cc → binário nativo
```

Referência: [https://en.wikipedia.org/wiki/Ahead-of-time_compilation](https://en.wikipedia.org/wiki/Ahead-of-time_compilation)

---

### QBE — Compilador de Backend Leve

QBE (*Quick Backend*) é um compilador de backend minimalista escrito em C, desenvolvido por Quentin Carbonneaux. Ele recebe um IR próprio (arquivos `.ssa`) e gera código de máquina nativo de alta qualidade para x86-64, ARM64 e RISC-V.

O QBE ocupa um nicho entre backends pesados como LLVM (que gera código excelente mas tem compilação lenta e API complexa) e backends triviais sem otimização. O QBE aplica um conjunto sólido de otimizações — eliminação de código morto, alocação de registradores por coloração de grafo, SSA (*Static Single Assignment*) — em menos de 15 mil linhas de C, resultando em tempo de compilação muito baixo.

Na Harpy, `QBECodeGen` traduz a AST para o IR textual do QBE (`.ssa`), que é então compilado pelo binário `qbe` e montado pelo `cc` do sistema.

Repositório oficial: [https://c9x.me/compile/](https://c9x.me/compile/)

---

### JIT — Compilação em Tempo de Execução (*Just-in-Time*)

Compilação em tempo de execução é o modelo em que o código é compilado para código de máquina **durante** a execução do programa, tipicamente logo antes de cada trecho de código ser executado pela primeira vez. O compilador é parte do runtime — ele existe dentro do processo em execução.

Vantagens: elimina a etapa de compilação prévia, permite introspecção e geração de código dinâmica, tempo de inicialização muitas vezes menor que AOT completo para programas curtos.
Desvantagem: há um custo de compilação no início da execução; o processo precisa carregar o compilador JIT em memória.

Na Harpy, o modo JIT passa pelo seguinte pipeline:

```
.hp → parser → MIRCodeGen → IR MIR em memória → MIR JIT → execução nativa
```

Nenhum arquivo intermediário é escrito em disco. Tudo acontece em memória.

Referência: [https://en.wikipedia.org/wiki/Just-in-time_compilation](https://en.wikipedia.org/wiki/Just-in-time_compilation)

---

### MIR — Representação Intermediária Leve com JIT Integrado

MIR (*Medium-level Intermediate Representation*) é uma biblioteca C desenvolvida por Vladimir Makarov (vnmakarov), parte do projeto GCC. Ela define uma representação intermediária compacta e um compilador JIT de alta performance que a executa.

O MIR se destaca por ser extremamente rápido na geração e compilação do código: o tempo de JIT para programas típicos opera na casa das centenas de microssegundos. Ele oferece três níveis de execução — interpretação pura, compilação leve (sem otimização) e compilação completa com otimizações — e expõe uma API C direta para construção programática do IR em memória.

Na Harpy, `MIRCodeGen` constrói o IR MIR diretamente em memória a partir da AST (via `mir_api.d` e os bindings em `mir.d`), sem passar por representação textual intermediária. O resultado é compilado e executado pelo runtime MIR dentro do mesmo processo.

Repositório oficial: [https://github.com/vnmakarov/mir](https://github.com/vnmakarov/mir)

---

## Pipeline de Compilação

O compilador recebe um arquivo de entrada (`.hp`) e executa três passes internos em sequência:

```
Arquivo .hp → Análise Léxica → Análise Sintática + Semântica → Geração de Código
```

Todos os passes são deliberadamente enxutos e rápidos. O tempo total de compilação opera na casa dos **microssegundos (µs)**, mesmo para programas não triviais.

### 1. Análise Léxica (Lexer)

Transforma o texto bruto em uma sequência de tokens. Reconhece:

- Palavras-chave (`funcao`, `função`, `fn`, `estrutura`, `alocar`, `alocarn`, `imediato`, `ime`, `retorne`, `ret`, `salte`, `saltez`, `saltenz`, `compare`, `chamada`, `ref`, `deref`, `escreva`, `obter`, `setar`, `conv`, `soma`, `sub`, `mul`, `mod`)
- Identificadores (`$nome`, `.label`, `NomeTipo`)
- Literais inteiros, decimais e strings
- Operadores e pontuação
- Comentários de linha (`//`)

### 2. Análise Sintática + Semântica (Parser)

Realiza análise sintática e semântica **em um único passe**, sem árvore intermediária separada para validação. Isso significa que todo o programa é validado antes de qualquer geração de código.

Durante o parsing, são resolvidos:

- Verificação de existência de variáveis e funções no escopo atual
- Verificação de tipos em operações binárias e atribuições
- Determinação do tamanho dos tipos primitivos
- Cálculo de tamanho, alinhamento e offset de campos em structs

O resultado é uma **AST enxuta**: sem nós descartáveis, sem anotações desnecessárias — apenas o suficiente para alimentar os backends.

### 3. Geração de Código

Depende do modo escolhido na invocação:

| Flag | Backend | Resultado |
|------|---------|-----------|
| `--aot` ou `-A` | QBE | Binário estático nativo |
| `--jit` ou `-J` | MIR (vnmakarov/mir) | Execução dinâmica em tempo de execução |

Ambos produzem resultados equivalentes para qualquer IR válido. A escolha do backend não afeta a semântica do programa.

---

## Invocação

```
harpy <arquivo.hp> [modo] [flags]
```

**Modos (obrigatório escolher um):**

| Flag | Descrição |
|------|-----------|
| `--jit`, `-J` | Executa via JIT (MIR) |
| `--aot`, `-A` | Compila para binário nativo (QBE + cc) |

**Flags gerais:**

| Flag | Descrição |
|------|-----------|
| `--tempo`, `-T` | Exibe o tempo de cada passe interno em µs |
| `--saida <path>`, `-s <path>` | Caminho de saída do binário (padrão: mesmo diretório do `.hp` sem extensão) |
| `--versao`, `-v` | Exibe a versão do compilador |

**Flags de debug (inspeção intermediária):**

| Flag | Descrição |
|------|-----------|
| `--ast` | Imprime a AST após o parsing |
| `--asm` | Mantém o arquivo `.s` gerado pelo QBE (só AOT) |
| `--ssa` | Mantém o arquivo `.ssa` de IR QBE (só AOT) |
| `--mir` | Imprime o MIR gerado antes da execução JIT |

**Pipeline AOT detalhado:**

```
arquivo.hp → lexer → parser → QBECodeGen → arquivo.ssa → qbe → arquivo.s → cc → binário
```

Os arquivos intermediários `.ssa` e `.s` são deletados automaticamente após a compilação, a menos que `--ssa` ou `--asm` sejam passados.

**Exemplos:**
```sh
harpy exemplos/ola.hp --jit
harpy exemplos/estresse.hp -J --tempo
harpy exemplos/main.hp --aot
harpy exemplos/main.hp -A -s out/programa
harpy exemplos/main.hp -A --ssa --asm    # mantém arquivos intermediários
harpy exemplos/main.hp -J --ast          # imprime AST e executa
```

---

## AST

O parser produz uma árvore com os seguintes tipos de nós (`NodeKind`):

| Nó | Descrição |
|----|-----------|
| `Program` | Raiz — lista de declarações (`FuncDecl` e `StructDecl`) |
| `FuncDecl` | Declaração de função: nome, tipo de retorno, argumentos, corpo, flags `isExtern`/`isVariadic` |
| `StructDecl` | Declaração de struct: nome e lista de `StructField` com offset e padding já calculados |
| `LabelStmt` | Label com seu bloco de instruções subordinadas |
| `InstructionStmt` | Instrução genérica — carrega um `Instruction` enum e operandos `a`, `b`, `c`, `d`, `e`, `f` |
| `CallExpr` | Chamada de função: nome + lista de argumentos (`string[]`) |
| `Identifier` | Identificador simples (nome de tipo, campo, label) |
| `IDentifier` | Identificador prefixado com `$` (variável) |
| `IntLit` | Literal inteiro (`long`) |
| `DoubleLit` | Literal de ponto flutuante (`double`) — tipo inferido como `f64` |
| `StringLit` | Literal de string — tipo inferido como `i64` (ponteiro) |

### Instruções (`Instruction` enum)

| Valor | Instrução IR |
|-------|-------------|
| `Aloca` | `alocar` |
| `Alocan` | `alocarn` |
| `Ime` | `imediato` / `ime` |
| `Ret` | `retorne` / `ret` |
| `Chamada` | `chamada` |
| `Conv` | `conv` / `converter` |
| `Setar` | `setar` |
| `Obter` | `obter` |
| `Salte` | `salte` |
| `Saltez` | `saltez` |
| `Saltenz` | `saltenz` |
| `Compare` | `compare` |
| `Aritmetica` | `soma`, `sub`, `mul`, `div`, `mod` — operador guardado em `InstructionStmt.op` |
| `Ref` | `ref` |
| `Deref` | `deref` |
| `Escreva` | `escreva` |

---

## Contexto e Análise Semântica

O `Context` mantém o estado semântico durante o parsing:

- **Tabela de variáveis:** mapeia `$nome → ContextValue { type, value, isConst }`. Toda variável é registrada no momento do `alocar`. Usos antes do `alocar` são um erro.
- **Tabela de funções:** mapeia nome → declaração. Registrada no momento do `parseFnDecl`.
- **`isConst`:** flag que indica se o valor de uma variável é provável em compile-time. Setado como `true` quando a variável recebe um `imediato` com literal. Utilizado pela instrução `alocarn` para validar o tamanho do bloco.

O `TypeRegistry` mantém o mapa de tipos conhecidos (primitivos + structs registradas). É consultado por `parseType()` e populado em `parseStructDecl()`.

### Verificações feitas durante o parsing

- Tipo de cada operando em todas as instruções (via `checkType`)
- Existência de variável antes do uso (via `context.tryGetVar`)
- Tipo do ponteiro em `ref` — exige `i64` no destino
- Valor comptime em `alocarn` — exige `isConst == true` e `IntLit > 0`
- Unicidade de campos em structs
- Unicidade de nomes de structs no registry

---

### Filosofia

O IR da Harpy é intencionalmente **verboso e explícito**. Cada instrução opera diretamente sobre variáveis nomeadas em memória. A única instrução capaz de introduzir um valor literal é `imediato`. Todo o resto lê e escreve variáveis.

Consequências diretas:

- **Sem conversões implícitas** — toda conversão de tipo é explícita via `conv`
- **Sem fluxo implícito** — todo desvio é um salto nomeado
- **Sem aritmética implícita** — todo cálculo intermédio precisa de uma variável
- **Fortemente tipado** — toda instrução carrega o tipo sobre o qual opera

Essa explicitidade beneficia tanto o compilador (otimizações triviais, análise de fluxo direta) quanto o leitor (nada é escondido).

O IR foi projetado para ser gerado por compiladores, não escrito à mão — embora isso seja completamente possível e válido. A Harpy expõe uma **API de construção de IR** com açúcar sintático para operações comuns como indexação de arrays, acesso a campos de structs e gerenciamento de temporários.

---

### Tipos

#### Primitivos

| Tipo | Descrição | Tamanho |
|------|-----------|---------|
| `void` | ausência de valor (só em retorno) | 0 bytes |
| `i1` | booleano / inteiro 1 bit | 1 byte |
| `i8` | inteiro com sinal de 8 bits | 1 byte |
| `i16` | inteiro com sinal de 16 bits | 2 bytes |
| `i32` | inteiro com sinal de 32 bits | 4 bytes |
| `i64` | inteiro com sinal de 64 bits / ponteiro | 8 bytes |
| `u8` | inteiro sem sinal de 8 bits | 1 byte |
| `u16` | inteiro sem sinal de 16 bits | 2 bytes |
| `u32` | inteiro sem sinal de 32 bits | 4 bytes |
| `u64` | inteiro sem sinal de 64 bits | 8 bytes |
| `f32` | ponto flutuante de 32 bits | 4 bytes |
| `f64` | ponto flutuante de 64 bits | 8 bytes |

> **Nota:** ponteiros são sempre representados como `i64`. Não existe um tipo ponteiro distinto — qualquer `i64` pode conter um endereço de memória.

#### Tipos Definidos pelo Usuário (Structs)

Declarados com a palavra-chave `estrutura`. Harpy calcula automaticamente tamanho, alinhamento e offsets dos campos durante o parsing.

```
estrutura <Nome> {
    <tipo> <campo>,
    <tipo> <campo>
}
```

Exemplo:

```
estrutura Usuario {
    i64 nome,   // 8 bytes — ponteiro para string
    i16 idade   // 2 bytes + 6 bytes de padding
}
```

O tamanho total da struct respeita as regras de alinhamento da plataforma alvo.

---

### Variáveis

Toda variável deve ser declarada com `alocar` antes de ser usada. Variáveis são prefixadas com `$`.

```
alocar <tipo>, $nome
```

Exemplos:

```
alocar i32, $x
alocar i64, $ptr
alocar f64, $valor
alocar Usuario, $u
```

Para alocar um bloco contíguo de N elementos na **stack**, usa-se `alocarn`:

```
alocarn <tipo_elemento>, $ptr_destino, $count
```

Onde `$ptr_destino` é um `i64` (ponteiro para o início do bloco) e `$count` é uma variável cujo valor **precisa ser provável em tempo de compilação** (comptime-constant). O tamanho total alocado na stack é `sizeof(tipo_elemento) * count`.

> **Restrição:** `$count` deve ter sido atribuída via `imediato` com um valor literal inteiro positivo antes da instrução `alocarn`. Valores que dependem de fluxo de controle ou de chamadas de função são rejeitados com erro em compilação. Isso é verificado pelo parser via `ContextValue.isConst`.

---

### Instruções

#### `imediato` / `ime`

Atribui um valor literal a uma variável.

```
imediato <tipo>, $var, <valor>
ime <tipo>, $var, <valor>
```

É a **única instrução** que aceita um valor literal como operando. Strings são literais válidos para `i64` (pois strings são ponteiros).

```
imediato i32, $x, 42
ime i64, $str, "Olá Mundo!\n"
ime f64, $pi, 3.14
```

#### Operações Aritméticas

Todas as operações aritméticas têm a forma:

```
<op> <tipo>, $dest, $esq, $dir
```

| Instrução | Operação |
|-----------|----------|
| `soma` | `$dest = $esq + $dir` |
| `sub` | `$dest = $esq - $dir` |
| `mul` | `$dest = $esq * $dir` |
| `div` | `$dest = $esq / $dir` |
| `mod` | `$dest = $esq % $dir` |

Exemplos:

```
soma i32, $res, $a, $b
sub  i64, $off, $ptr, $base
mul  i32, $area, $w, $h
mod  i32, $resto, $n, $dois
```

#### `compare`

Compara duas variáveis e armazena o resultado (`i1`) em uma terceira.

```
compare <tipo>, $esq <op> $dir, $dest
```

Operadores suportados: `==`, `!=`, `<`, `<=`, `>`, `>=`

```
compare i32, $i != $limite, $cond
compare i32, $n < $dois,    $cond
```

#### Saltos e Labels

Labels são identificadores prefixados com `.` e definem pontos de desvio dentro de uma função.

```
.nome_do_label:
```

**Salto incondicional:**

```
salte .<label>
```

**Salto condicional — salta se zero (`i1 == 0`):**

```
saltez $cond, .<label_se_zero>, .<label_se_nao_zero>
```

**Salto condicional — salta se não-zero (`i1 != 0`):**

```
saltenz $cond, .<label_se_nao_zero>, .<label_se_zero>
```

Exemplo — estrutura de if/else:

```
compare i32, $ret != $val, $res
saltez $res, .erro, .sucesso

.sucesso:
    imediato i32, $ret, 0
    salte .fim

.erro:
    imediato i32, $ret, 1
    salte .fim

.fim:
    retorne $ret
```

Exemplo — loop:

```
.loop:
    compare i32, $i != $limite, $cond
    saltez $cond, .fim, .corpo

.corpo:
    soma i32, $soma, $soma, $i
    soma i32, $i, $i, $um
    salte .loop

.fim:
    retorne $soma
```

#### Ponteiros

**`ref`** — obtém o endereço de uma variável:

```
ref $var, $ptr   // $ptr (i64) = &$var
```

**`deref`** — lê o valor apontado:

```
deref $ptr, $dest   // $dest = *$ptr
```

**`escreva`** — escreve um valor no endereço apontado:

```
escreva $ptr, $val   // *$ptr = $val
```

Exemplo:

```
alocar i32, $a
alocar i64, $b
alocar i32, $c
alocar i32, $d

imediato i32, $a, 100
imediato i32, $c, 67

ref   $a, $b      // $b = &$a
escreva $b, $c    // *$b = $c  →  $a agora vale 67
deref $b, $d      // $d = *$b  →  $d = 67

retorne $d        // retorna 67
```

#### Acesso a Structs

**`setar`** — escreve em um campo da struct:

```
setar <NomeStruct>, $instancia, <campo>, $valor
```

**`obter`** — lê um campo da struct:

```
obter <NomeStruct>, $instancia, <campo>, $dest
```

Exemplo:

```
alocar Usuario, $u
alocar i64, $nome1
alocar i64, $nome2

imediato i64, $nome1, "Fernandu\n"

setar Usuario, $u, nome, $nome1   // u.nome = $nome1
obter Usuario, $u, nome, $nome2   // $nome2 = u.nome
```

#### `conv`

Converte um valor de um tipo para outro. Toda conversão de tipo é **sempre explícita**.

```
conv <tipo_origem>, <tipo_destino>, $src, $dest
```

```
alocar f64, $x
alocar i32, $z
ime f64, $x, 60.0
conv f64, i32, $x, $z   // $z = (i32) $x
```

#### `chamada` / Chamadas de Função

```
chamada <tipo_retorno>, <nome>(<args>), $dest
```

Onde `$dest` é a variável que receberá o valor de retorno.

```
chamada i32, soma($a, $b), $resultado
chamada i32, printf($fmt, $total), $r1
```

Para funções variádicas (como `printf` da libc), usa-se `...` na declaração:

```
funcao i32 printf(i64 $msg, ...);
```

#### `retorne` / `ret`

Retorna um valor da função atual.

```
retorne $var
ret $var
```

---

### Funções

#### Declaração

```
funcao <tipo_retorno> <nome>(<params>) {
    <corpo>
}
```

Aliases aceitos para a palavra-chave: `funcao`, `função`, `fn`.

Parâmetros usam a forma `<tipo> $nome`:

```
funcao i32 soma(i32 $x, i32 $y) {
    alocar i32, $res
    soma i32, $res, $x, $y
    retorne $res
}
```

#### Declaração Externa (FFI)

Para chamar funções externas (como da libc), declara-se a assinatura sem corpo:

```
funcao i32 printf(i64 $msg, ...);
```

---

### Palavras-chave Aceitas

Harpy aceita múltiplos aliases para a maioria das palavras-chave, tornando o IR mais tolerante e legível:

| Canônico | Aliases aceitos |
|----------|----------------|
| `funcao` | `função`, `fn` |
| `retorne` | `ret` |
| `imediato` | `ime` |
| `sub` | `subtracao`, `subtração` |
| `mul` | `multiplicacao`, `multiplicação` |
| `div` | `divisão` |
| `mod` | `modulo` |
| `ref` | `referencia` |
| `deref` | `dereferencia` |
| `conv` | `converter` |
| `alocar` | — |
| `alocarn` | — |
| `salte` | — |
| `saltez` | — |
| `saltenz` | — |
| `compare` | — |
| `chamada` | — |
| `escreva` | — |
| `setar` | — |
| `obter` | — |
| `soma` | — |
| `estrutura` | — |

---

## API de Construção de IR

Harpy expõe uma API de alto nível para gerar IR programaticamente a partir de um compilador-alvo. A API elimina operações manuais verbosas (como calcular índices e offsets de arrays) através de métodos utilitários.

Exemplos de operações que a API abstrai:

- Indexação de arrays: ao invés de calcular `$ptr = $base + $idx * sizeof(T)` manualmente, existe um método que recebe o ponteiro base, o índice e o tipo e emite todas as instruções necessárias
- Acesso a campos de struct com offsets automáticos
- Gerenciamento de registradores virtuais temporários

---

## Estrutura do Projeto

```
.
├── api/
│   ├── api.d          # API de construção de IR — interface D
│   └── api.ts         # API de construção de IR — interface TypeScript
├── src/
│   ├── main.d         # entrypoint — parsing de flags e orquestração dos passes
│   ├── lexer.d        # análise léxica
│   ├── token.d        # definição dos tokens
│   ├── parser.d       # análise sintática + semântica (passe único)
│   ├── ast.d          # definição dos nós da AST
│   ├── htype.d        # sistema de tipos (HType, HTypeBuiltin, HTypeStruct)
│   ├── type_registry.d# registro global de tipos definidos pelo usuário (structs)
│   ├── context.d      # contexto de compilação (escopos, variáveis, funções)
│   ├── errors.d       # formatação e emissão de erros
│   ├── utils.d        # utilitários gerais
│   └── backend/
│       ├── jit/
│       │   ├── codegen.d   # geração de código JIT — travessia da AST
│       │   ├── mir_api.d   # wrapper sobre a API C do MIR
│       │   └── mir.d       # bindings D para a biblioteca MIR
│       └── qbe/
│           ├── codegen.d   # geração de código AOT — travessia da AST
│           └── qbe_api.d   # wrapper sobre a API C do QBE
├── exemplos/
│   ├── ola_mundo.hp   # hello world via printf
│   ├── exemplo0.hp    # retorno de imediato
│   ├── exemplo1.hp    # chamada de função simples
│   ├── exemplo2.hp    # conversão de tipo (f64 → i32)
│   ├── loop.hp        # loop com acumulador (0+1+...+9 = 45)
│   ├── compare.hp     # desvio condicional com compare + saltez
│   ├── salte.hp       # saltos incondicionais entre labels
│   ├── ponteiro.hp    # ref / deref / escreva
│   ├── alocarn.hp     # alocação dinâmica de array
│   ├── alocarn2.hp    # indexação e leitura de array
│   ├── estrutura.hp   # declaração e acesso a struct (setar/obter)
│   └── estresse.hp    # programa combinando fib, fatorial, loop, ponteiro, struct
├── tests/
│   └── unit.d         # testes unitários
├── out/               # binários gerados por --aot
├── dub.json           # manifesto do projeto (D / dub)
├── dub.selections.json
├── harpy              # binário do compilador
├── README.md
├── IDEIA.md
├── ESPECIFICACOES.md
└── LICENSE
```

### Responsabilidades por módulo

| Módulo | Responsabilidade |
|--------|-----------------|
| `main.d` | Lê flags (`--aot`/`--jit`/`--tempo`), instancia os passes e mede tempo de cada etapa |
| `lexer.d` + `token.d` | Tokenização do arquivo `.hp` |
| `parser.d` | Parsing + análise semântica simultânea; produz a AST |
| `ast.d` | Nós da AST: declarações de função, struct, instrução, expressão |
| `htype.d` | Hierarquia de tipos (`HType`, `HTypeBuiltin`, `HTypeStruct`) com `getSize()` |
| `type_registry.d` | Mapa global nome → `HType`; consultado durante o parsing para resolver tipos de structs |
| `context.d` | Pilha de escopos, tabela de símbolos (variáveis e funções), registradores virtuais |
| `errors.d` | Erros com localização (linha/coluna) e mensagem descritiva |
| `backend/jit/codegen.d` | Travessia da AST emitindo instruções MIR; chama `mir_api.d` |
| `backend/jit/mir_api.d` | Wrapper de alto nível sobre os bindings MIR |
| `backend/jit/mir.d` | Bindings D para a biblioteca C `vnmakarov/mir` |
| `backend/qbe/codegen.d` | Travessia da AST emitindo texto QBE IR; chama `qbe_api.d` |
| `backend/qbe/qbe_api.d` | Wrapper de alto nível sobre a API C do QBE |
| `api/api.d` + `api/api.ts` | API pública para geração de IR Harpy a partir de compiladores externos |

---

## Exemplos

### Olá Mundo

```
funcao i32 printf(i64 $message, ...);

funcao i32 main() {
    alocar i64, $str
    ime i64, $str, "Olá Mundo!\n"

    alocar i32, $res
    chamada i32, printf($str), $res

    alocar i32, $x
    ime i32, $x, 0
    ret $x
}
```

### Loop — soma 0..9

```
funcao i32 main() {
    alocar i32, $i
    alocar i32, $soma
    alocar i32, $limite
    alocar i32, $cond

    imediato i32, $i, 0
    imediato i32, $soma, 0
    imediato i32, $limite, 10

.loop:
    compare i32, $i != $limite, $cond
    saltez $cond, .fim, .corpo

.corpo:
    soma i32, $soma, $soma, $i
    alocar i32, $um
    imediato i32, $um, 1
    soma i32, $i, $i, $um
    salte .loop

.fim:
    retorne $soma  // 45
}
```

### Recursão — Fibonacci

```
funcao i32 fib(i32 $n) {
    alocar i32, $cond
    alocar i32, $dois
    alocar i32, $um
    alocar i32, $res
    alocar i32, $n1
    alocar i32, $n2
    alocar i32, $ra
    alocar i32, $rb

    imediato i32, $um, 1
    imediato i32, $dois, 2

    compare i32, $n < $dois, $cond
    saltenz $cond, .base, .recursivo

.base:
    retorne $n

.recursivo:
    sub i32, $n1, $n, $um
    sub i32, $n2, $n, $dois
    chamada i32, fib($n1), $ra
    chamada i32, fib($n2), $rb
    soma i32, $res, $ra, $rb
    retorne $res
}
```

### Conversão de Tipo

```
funcao i32 main() {
    alocar f64, $x
    alocar i32, $z

    ime f64, $x, 60.0
    conv f64, i32, $x, $z  // cast explícito

    ret $z  // retorna 60
}
```
