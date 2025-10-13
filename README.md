# ReprInter

Representação Intermediária 100% em português.

## Motivação

Assim como existem diversas implementações de máquinas virtuais em linguagens de programação em inglês, como JVM para Java, IR para .NET, LLVM para C, C++ e Rust, é interessante para a conunidade lusófona entender como funciona uma representação intermediária. 

Este repositório se dedica não apenas a documentar como funciona essa representação intermediária, como também a fornecer exemplos funcionais e ferramentas para a compilação dessa representação intermdiária em código binário. 

## Exemplos

```
// suporte a importação de outros arquivos. Copiará todas as funções e constantes
// para o novo contexto (contexto do arquivo que fez a importação)
// exemplo de sintaxe:
incluir "nome_do_arquivo.rp"
// a extensão .rp vem de ReprInter

// ReprInter viabiliza implementar uma VM (_Virtual Machine_, ou Máquina Virtual) baseada em _Stack_ (pilha).
// Tudo definido com % será uma variavel, seja temporária ou não.
// Variáveis temporárias serão criadas automaticamente com um _front-end_ (camada superior) geradora de código ReprInter.

// Todo código ReprInter requer um ponto de entrada.
// O ponto de entrada não tem retorno.
declarar principal() vazio {
    alocar %0, i32
    %0 = chamar somar(60, 9)
    chamar escreva(%0)
    fim
}

// ...    = variádico com qualquer tipo (vazio*)
// ...i32 = variádico com tipo i32 (i32*)
declarar escreva(...i32) vazio {
    escrevaPonteiro variadico // a variavel variádica é criada automaticamente
    // `escrevaPonteiro` é uma instrução que irá escrever tudo que contém dentro do variádico independente do tipo
    // caso tenha um asterisco - * - então o método aceita variádico com qualquer tipo
    // ou variádico será `T*` ou `vazio*`, dependerá da assinatura da função
}

// i32 = inteiro de 32 bits
declarar somar(x i32, y i32) i32 {
    alocar %resultado, i32 // %resultado recebe o endereço dele na pilha, o `adicionar` a seguir irá editar esse valor
    adicionar %resultado, x, y
    retornar %resultado
}
```
