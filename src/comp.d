module comp;

enum HVMOpCode : ubyte {
    Loadk, // carrega uma constante do pool
    Loadkx, // carregar uma constante com IDX grande do pool
    Call, // chamada em função normal com `ret`
    Callb, // chamada em função builtin
    Callf, // chamada em função ffi
    Ret, // retorna pro `pc` anterior
    
    // genericos pra qualquer tipo prevalecendo o tipo maior, suportam fastPath para operações com o mesmo tipo
    // prefixo B indica BitWise
    Add, // +
    Sub, // -
    Mul, // *
    Div, // /
    BShl, // >>
    BShll, // >>>
    BShr, // <<
    BXor, // ^
    BAnd, // &
    BNot, // ~
    Lt, // <
    Gt, // >
    Lte, // <=
    Gte, // >=
    Eq, // ==
    Neq, // !=
    
    Hlt,
}

import std.stdio;

uint encode(ubyte opcode, ubyte a = 0, ubyte b = 0, ubyte c = 0)
{
    return opcode | (a << 8) | (b << 16) | (c << 24);
}

uint encode2(ubyte opcode, ushort val)
{
    return opcode | (val << 8);
}

void main()
{
    File f = File("ola_mundo.hvm", "wb");
    // numero magico de 19 bytes
    f.rawWrite(cast(ubyte[])"HarpyVirtualMachine");
    // versão do binario
    // tamanho do programa
    // tamanho do constant pool
    ubyte ver = 1;
    f.rawWrite([ver]);
    uint progSize = 4;
    uint poolSize = 2;
    f.rawWrite([progSize, poolSize]);
    // programa
    f.rawWrite([
        encode2(HVMOpCode.Loadk, 0),
        encode2(HVMOpCode.Loadk, 1),
        encode(HVMOpCode.Add),
        encode(HVMOpCode.Hlt)
    ]);
    // pool de constantes

    ubyte t = 6;
    int v1 = 60;
    int v2 = 9;

    f.rawWrite([t]);
    f.rawWrite([v1]);
    f.rawWrite([t]);
    f.rawWrite([v2]);
    
    f.close();
}
