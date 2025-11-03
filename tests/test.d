module tests.test;

import std.stdio;
import lib.d.harpy_modulo, lib.d.harpy_bloco, lib.d.harpy_contador, lib.d.harpy_funcao, lib
    .d.harpy_valor;

void main()
{
    HarpyModulo modulo = new HarpyModulo("teste.rp");

    HarpyFuncao principal = new HarpyFuncao("principal", HarpyTipo.Vazio, []);
    HarpyBloco bloco = new HarpyBloco(new HarpyContadorTemporario);
    principal.definirBloco(bloco);

    HarpyValor x = bloco.var("x", HarpyTipo.Int, "60");
    HarpyValor y = bloco.var("y", HarpyTipo.Int, "9");
    bloco.print(bloco.call("soma", HarpyTipo.Int, [x, y]));
    bloco.fim();

    HarpyFuncao soma = new HarpyFuncao("soma", HarpyTipo.Int, [
            HarpyValor("x", HarpyTipo.Int), HarpyValor("y", HarpyTipo.Int)
        ]);
    HarpyBloco bloco_soma = new HarpyBloco(new HarpyContadorTemporario);
    soma.definirBloco(bloco_soma);
    bloco_soma.ret(bloco_soma.add(HarpyTipo.Int, soma.getArg(0), soma.getArg(1)));

    modulo.addFuncao(soma);
    modulo.addFuncao(principal);

    writeln(modulo.gerar());
}
