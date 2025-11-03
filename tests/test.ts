import {
    HarpyBloco,
    HarpyContadorTemporario,
    HarpyFuncao,
    HarpyModulo,
    HarpyTipo,
} from "../src/lib/ts/harpy.ts";

const modulo = new HarpyModulo("main.rp");

const soma = new HarpyFuncao("soma", HarpyTipo.Int, [
    modulo.criarValor("x", HarpyTipo.Int),
    modulo.criarValor("y", HarpyTipo.Int),
]);

const soma_bloco = new HarpyBloco(new HarpyContadorTemporario());
soma.definirBloco(soma_bloco);
soma_bloco.ret(soma_bloco.add(
    HarpyTipo.Int,
    soma.getArg(0),
    soma.getArg(1),
));

const principal = new HarpyFuncao("principal", HarpyTipo.Vazio, []);
const principal_bloco = new HarpyBloco(new HarpyContadorTemporario());
principal.definirBloco(principal_bloco);

const x = principal_bloco.var("x", HarpyTipo.Int, "60");
const y = principal_bloco.varTmpValue(HarpyTipo.Int, "9");
const z = principal_bloco.call("soma", HarpyTipo.Int, [x, y]);
principal_bloco.print(z);
principal_bloco.fim();

modulo.addFuncao(soma);
modulo.addFuncao(principal);

console.log(modulo.gerar());
