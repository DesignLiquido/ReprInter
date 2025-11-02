import HarpyFuncao from "./harpy_funcao.ts";
import { HarpyTipo, HarpyValor } from "./harpy_valor.ts";

export default class HarpyModulo {
    private nome: string;
    private functions: HarpyFuncao[] = [];

    constructor(nome: string = "main.fir") {
        this.nome = nome;
    }

    criarValor(
        valor: string = "",
        tipo: HarpyTipo = HarpyTipo.Vazio,
    ): HarpyValor {
        return { valor, tipo } as HarpyValor;
    }

    addFuncao(func: HarpyFuncao): void {
        this.functions.push(func);
    }

    gerar(): string {
        return this.functions.map((f) => f.gen()).join("\n");
    }
}
