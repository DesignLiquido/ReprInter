enum HVMOpCode {
    Loadk = 0,  // carrega uma constante do pool
    Loadkx,     // carregar uma constante com IDX grande do pool
    Call,       // chamada em função normal com `ret`
    Callb,      // chamada em função builtin
    Callf,      // chamada em função ffi
    Ret,        // retorna pro `pc` anterior
    // genericos pra qualquer tipo prevalecendo o tipo maior, suportam fastPath para operações com o mesmo tipo
    // prefixo B indica BitWise
    Add,        // +
    Sub,        // -
    Mul,        // *
    Div,        // /
    BShl,       // >>
    BShll,      // >>>
    BShr,       // 
    BXor,       // ^
    BAnd,       // &
    BNot,       // ~
    Lt,         // 
    Gt,         // >
    Lte,        // <=
    Gte,        // >=
    Eq,         // ==
    Neq,        // !=
    Hlt,
}

function encode(opcode: number, a: number = 0, b: number = 0, c: number = 0): number {
    return opcode | (a << 8) | (b << 16) | (c << 24);
}

function encode2(opcode: number, val: number): number {
    return opcode | (val << 8);
}

async function main() {
    const chunks: Uint8Array[] = [];
    
    // numero magico de 19 bytes
    const magicNumber = new TextEncoder().encode("HarpyVirtualMachine");
    chunks.push(magicNumber);
    
    // versão do binario
    const ver = new Uint8Array([1]);
    chunks.push(ver);
    
    // tamanho do programa
    const progSize = new Uint32Array([4]);
    chunks.push(new Uint8Array(progSize.buffer));
    
    // tamanho do constant pool
    const poolSize = new Uint32Array([2]);
    chunks.push(new Uint8Array(poolSize.buffer));
    
    // programa
    const program = new Uint32Array([
        encode2(HVMOpCode.Loadk, 0),
        encode2(HVMOpCode.Loadk, 1),
        encode(HVMOpCode.Add),
        encode(HVMOpCode.Hlt)
    ]);
    chunks.push(new Uint8Array(program.buffer));
    
    // pool de constantes
    const t = new Uint8Array([6]);
    const v1 = new Int32Array([60]);
    const v2 = new Int32Array([9]);
    
    chunks.push(t);
    chunks.push(new Uint8Array(v1.buffer));
    chunks.push(t);
    chunks.push(new Uint8Array(v2.buffer));
    
    // Combinar todos os chunks em um único array
    const totalLength = chunks.reduce((acc, chunk) => acc + chunk.length, 0);
    const finalBuffer = new Uint8Array(totalLength);
    
    let offset = 0;
    for (const chunk of chunks) {
        finalBuffer.set(chunk, offset);
        offset += chunk.length;
    }
    
    // Escrever no arquivo
    await Deno.writeFile("js.hvm", finalBuffer);
    console.log("Arquivo criado com sucesso!");
}

// Executar
if (import.meta.main) {
    main();
}
