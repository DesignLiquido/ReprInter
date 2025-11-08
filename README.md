# ReprInter

**ReprInter** é uma representação intermediária (IR) projetada para a máquina virtual **HarpyVM** — uma VM leve, eficiente e focada em simplicidade.

---

## Sobre a HarpyVM

A **HarpyVM** é uma máquina virtual baseada em pilha (stack-based), desenvolvida com foco em:

- **Simplicidade**: Inspirada na filosofia de design do Lua, priorizando clareza e facilidade de uso
- **Performance**: Capaz de executar centenas de milhares ou até milhões de operações por segundo
- **Startup instantâneo**: Sem overhead de inicialização, ideal para execução rápida
- **Eficiência de memória**: Escrita em D, aproveita o garbage collector nativo da linguagem

Ao contrário de VMs complexas como o V8 (Google), a Harpy mantém uma arquitetura enxuta que facilita compreensão e manutenção, sem sacrificar desempenho.

### Características principais

- **IR próprio (ReprInter)**: Representação intermediária simples e direta que abstrai complexidades desnecessárias
- **Múltiplos frontends**: Geradores de IR disponíveis em D e TypeScript
- **Foco no essencial**: Implementação concentrada nas operações críticas, delegando aspectos secundários ao ecossistema D

---

## Motivação

Enquanto existem inúmeras implementações de máquinas virtuais e representações intermediárias documentadas em inglês (JVM para Java, IL para .NET, LLVM para C/C++/Rust), há uma lacuna de recursos educacionais em português sobre esse tema fundamental.

Este projeto tem como objetivos:

1. **Educação**: Explicar de forma clara e acessível como funciona uma representação intermediária
2. **Prática**: Fornecer exemplos funcionais e ferramentas prontas para uso
3. **Comunidade**: Contribuir para o ecossistema de desenvolvimento em língua portuguesa

Aqui você encontrará não apenas documentação teórica, mas também ferramentas para compilar HarpyVM em código binário executável.

---

## Licença

```
MIT License

Copyright (c) 2025 Fernando
Supported by Design Liquido

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
