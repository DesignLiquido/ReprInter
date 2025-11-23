# ReprInter

Extensão oficial do **ReprInter** para Visual Studio Code — suporte completo para a representação intermediária da **HarpyVM**.

---

## Sobre o ReprInter

**ReprInter** é a representação intermediária (IR) da **HarpyVM**, uma máquina virtual baseada em pilha, leve e eficiente, desenvolvida com foco em simplicidade e performance.

### Por que usar esta extensão?

- **Syntax Highlighting**: Destaque de sintaxe completo para arquivos `.rp`
- **Snippets**: Atalhos para padrões comuns de código

---

## Características da HarpyVM

A **HarpyVM** é uma máquina virtual projetada com princípios claros:

- **Simplicidade**: Inspirada no Lua, priorizando clareza e facilidade de uso
- **Performance**: Centenas de milhares de operações por segundo
- **Startup instantâneo**: Zero overhead de inicialização
- **Eficiência de memória**: Implementada em D com garbage collector nativo

### Diferenciais do ReprInter

- **IR simples e direto**: Abstrai complexidades desnecessárias
- **Múltiplos frontends**: Geradores disponíveis em D e TypeScript
- **Foco no essencial**: Operações críticas otimizadas

---

## Instalação

1. Abra o VS Code
2. Pressione `Ctrl+P` (ou `Cmd+P` no macOS)
3. Digite: `ext install reprinter`
4. Pressione Enter

Ou instale diretamente do [Marketplace](https://marketplace.visualstudio.com/items?itemName=FarpyOrganization.reprinter)

---

## Motivação

Enquanto existem inúmeros recursos sobre VMs e IRs em inglês (JVM, IL, LLVM), há uma lacuna em português. Este projeto visa:

1. **Educar**: Explicar IRs de forma clara e acessível
2. **Praticar**: Fornecer ferramentas funcionais e exemplos
3. **Comunidade**: Contribuir para o ecossistema brasileiro de desenvolvimento

---

## Requisitos

- Visual Studio Code 1.80.0 ou superior
- HarpyVM instalada (opcional, para execução)

---

## Problemas conhecidos

Reporte bugs e sugestões em: [GitHub Issues](https://github.com/DesignLiquido/ReprInter/issues)

---

## Roadmap

- [ ] Debugger integrado
- [ ] Visualizador de pilha em tempo real
- [ ] Profiler de performance
- [ ] Integração com Language Server Protocol (LSP)

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

---

## Links úteis

- [Especificação ReprInter](https://github.com/DesignLiquido/ReprInter)
- [Exemplos de código](https://github.com/DesignLiquido/ReprInter/exemplos/)
