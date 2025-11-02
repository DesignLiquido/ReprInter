import { HarpyTipo, HarpyValor } from "./harpy_valor.ts";
import HarpyBloco from "./harpy_bloco.ts";

export default class HarpyFuncao {
    private nome: string;
    private tipoDeRetorno: HarpyTipo;
    private params: HarpyValor[];
    private bloco!: HarpyBloco;

    constructor(
        nome: string,
        tipo: HarpyTipo,
        params: HarpyValor[] = [],
    ) {
        this.nome = nome;
        this.tipoDeRetorno = tipo;
        this.params = params;
    }

    getArg(index: number = 0): HarpyValor {
        // TODO: Validar
        return this.params[index];
    }

    definirBloco(bloco: HarpyBloco): void {
        this.bloco = bloco;
    }

    gen(): string {
        let code = "";
        code += `declarar ${this.nome} (`;
        for (let i = 0; i < this.params.length; i++) {
            code += this.params[i].valor;
            code += " ";
            code += this.params[i].tipo;
            if (!((i + 1) >= this.params.length)) {
                code += ", ";
            }
        }
        code += ") ";
        code += this.tipoDeRetorno;
        code += this.bloco.gerar();
        return code;
    }
}
