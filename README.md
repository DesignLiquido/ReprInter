# Harpy

Harpy é um backend para interpretadores e compiladores com uma representação intermediária (IR) totalmente em português — uma proposta inédita no Brasil.
Ela suporta tanto a geração de binários estáticos (AOT — *Ahead-of-Time*) quanto a interpretação da própria IR por meio de JIT (*Just-in-Time*).

Com isso, Harpy se torna o primeiro backend para compiladores desenvolvido no Brasil que utiliza uma IR inteiramente em português, facilitando o aprendizado e a experimentação na nossa língua nativa.

```rs
função i32 printf(i64 $message, ...); // função externa da libc

função i32 main() {
    aloca i64, $str
    ime i64, $str, "Olá Mundo!\n" // strings são ponteiros por padrão, e todo ponteiro é um i64

    aloca i32, $res
    chamada i32, printf($str), $res

    aloca i32, $x
    ime i32, $x, 0
    ret $x
}
```
