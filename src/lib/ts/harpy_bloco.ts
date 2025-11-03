import HarpyContadorTemporario from "./harpy_contador.ts";
import { HarpyTipo, HarpyValor } from "./harpy_valor.ts";

export default class HarpyBloco {
    private contador: HarpyContadorTemporario;
    private instrucoes: string[] = [];

    private emitir(codigo: string): void {
        this.instrucoes.push(codigo);
    }

    constructor(contador: HarpyContadorTemporario) {
        this.contador = contador;
    }

    varTmp(tipo: HarpyTipo): HarpyValor {
        const nome = String(this.contador.proximo());
        this.emitir(`alocar $${nome} ${tipo};`);
        return {
            valor: "$" + nome,
            tipo: tipo,
        } as HarpyValor;
    }

    varTmpValue(tipo: HarpyTipo, valor: string): HarpyValor {
        const nome = String(this.contador.proximo());
        this.emitir(`alocar $${nome} ${tipo} = ${valor}`);
        return {
            valor: "$" + nome,
            tipo: tipo,
        } as HarpyValor;
    }

    var(nome: string, tipo: HarpyTipo, valor: string): HarpyValor {
        this.emitir(`alocar ${nome} ${tipo} = ${valor}`);
        return {
            valor: nome,
            tipo: tipo,
        } as HarpyValor;
    }

    sargs(args: HarpyValor[]): string {
        let sargsResult = "";
        for (let i = 0; i < args.length; i++) {
            sargsResult += args[i].valor;
            // sargsResult += " ";
            // sargsResult += args[i].tipo;
            if (!((i + 1) >= args.length)) {
                sargsResult += ", ";
            }
        }
        return sargsResult;
    }

    call(fn: string, tipo: HarpyTipo, args: HarpyValor[]): HarpyValor {
        const sargsResult = this.sargs(args);
        return this.varTmpValue(tipo, `${fn}(${sargsResult})`);
    }

    callWithTarget(
        fn: string,
        args: HarpyValor[],
        target: HarpyValor,
    ): HarpyValor {
        const sargsResult = this.sargs(args);
        this.emitir(`${target.valor} = ${fn}(${sargsResult})`);
        return target;
    }

    add(tipo: HarpyTipo, x: HarpyValor, y: HarpyValor): HarpyValor {
        return this.varTmpValue(tipo, `${x.valor} + ${y.valor}`);
    }

    print(valor: HarpyValor): HarpyValor {
        this.emitir(`__nucleo_harpy_escreva(${valor.valor})`);
        return valor;
    }

    ret(valor: HarpyValor): HarpyValor {
        this.emitir(`retorne ${valor.valor}`);
        return valor;
    }

    fim(): HarpyValor {
        this.emitir("fim");
        return {
            valor: "\0",
            tipo: HarpyTipo.Vazio,
        } as HarpyValor;
    }

    gerar(): string {
        let codigo = " {\n";
        for (const instr of this.instrucoes) {
            codigo += "    " + instr + "\n";
        }
        codigo += "}\n";
        return codigo;
    }
}
