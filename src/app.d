module app;

import harpyvm;
import std.stdio, std.path, std.format;
import core.stdc.stdlib : exit, EXIT_FAILURE, free, malloc;

// tamanho minimo = NUMERO MAGICO + VERSAO + PS + CS
// tamanho minimo = 19 bytes + 1 byte + 4 bytes + 4 bytes = 28 bytes
const ubyte VERSAO = 1;
const string NUMERO_MAGICO = "HarpyVirtualMachine";
const ubyte TAMANHO_MINIMO = 28;

private struct Program {
    uint programSize;
    uint* program;
    HVMValue* constantPool;
    uint constantPoolSize;
}

Program makeProgram(string filename)
{
    Program p;
    File f = File(filename);
    if (f.size() < TAMANHO_MINIMO)
        error(format("O arquivo '%s' não pode ser um programa harpy válido!", filename));
    
    ubyte[19] NM = cast(ubyte[])NUMERO_MAGICO;
    ubyte[19] mn = f.rawRead(new ubyte[19]);
    if (mn != NM)
        error("O número mágico (MAGIC NUMBER) do programa é inválido.");

    // no futuro poderá haver mais versões do bytecode
    // vou deixar um erro aqui por padrão na primeira versão de todas
    ubyte[1] versao = f.rawRead(new ubyte[1]);
    if (versao[0] != VERSAO)
        error(format("A versão '%u' do programa não é válida.", versao[0]));
    
    uint[2] progPoolBuff = f.rawRead(new uint[2]);
    // pode ter ocorrido um erro ao ler
    uint progSize = progPoolBuff[0];
    if (progSize < 0 || progSize == uint.max)
        error(format("Erro ao ler o tamanho do programa '%u'.", progSize));
    
    uint poolSize = progPoolBuff[1];
    if (poolSize < 0 || poolSize == uint.max)
        error(format("Erro ao ler o tamanho do mapa de constantes '%u'.", poolSize));
    
    uint* program = cast(uint*) malloc(progSize * uint.sizeof);
    if (program is null)
        error("Ocorreu um erro ao alocar memória pro programa.");
    
    HVMValue* constantPool = cast(HVMValue*) malloc(poolSize * HVMValue.sizeof);
    if (constantPool is null)
    {
        free(program); // libera o programa alocado
        error("Ocorreu um erro ao alocar memória pro mapa de constantes.");
    }

    if (progSize > 0)
    {
        uint[] prog = f.rawRead(new uint[progSize]);
        // carrega o programa na memoria
        for (uint i; i < progSize; i++)
            program[i] = prog[i];
    }

    if (poolSize > 0)
    {
        // carregar os valores para a memoria é um pouco mais complexo
        // cada valor tem que ter o tipo respeitado e outras questões
        uint idx;
        for (uint i; i < poolSize; i++)
        {
            // todo valor tem o tipo como primeiro valor passado
            ubyte[1] tipo = f.rawRead(new ubyte[1]);
            switch (tipo[0]) {
                case HVMType.Bool:   constantPool[idx++] = HVMValue.makeBool((f.rawRead(new bool[1]))[0]); continue;
                case HVMType.Byte:   constantPool[idx++] = HVMValue.makeByte((f.rawRead(new byte[1]))[0]); continue;
                case HVMType.Ubyte:  constantPool[idx++] = HVMValue.makeUbyte((f.rawRead(new ubyte[1]))[0]); continue;
                case HVMType.Char:   constantPool[idx++] = HVMValue.makeChar((f.rawRead(new char[1]))[0]); continue;
                case HVMType.Short:  constantPool[idx++] = HVMValue.makeShort((f.rawRead(new short[1]))[0]); continue;
                case HVMType.Ushort: constantPool[idx++] = HVMValue.makeUshort((f.rawRead(new ushort[1]))[0]); continue;
                case HVMType.Int:    constantPool[idx++] = HVMValue.makeInt((f.rawRead(new int[1]))[0]); continue;
                case HVMType.Uint:   constantPool[idx++] = HVMValue.makeUint((f.rawRead(new uint[1]))[0]); continue;
                case HVMType.Long:   constantPool[idx++] = HVMValue.makeLong((f.rawRead(new long[1]))[0]); continue;
                case HVMType.Ulong:  constantPool[idx++] = HVMValue.makeUlong((f.rawRead(new ulong[1]))[0]); continue;
                case HVMType.Float:  constantPool[idx++] = HVMValue.makeFloat((f.rawRead(new float[1]))[0]); continue;
                case HVMType.Double: constantPool[idx++] = HVMValue.makeDouble((f.rawRead(new double[1]))[0]); continue;
                default:
                    error(format("Tipo desconhecido '%d'", tipo[0]));
                    break;
            }
        }
    }

    f.close();

    p.constantPool = constantPool;
    p.constantPoolSize = poolSize;
    p.program = program;
    p.programSize = progSize;

    return p;
}

void error(string msg)
{
    writefln("Erro: %s", msg);
    exit(EXIT_FAILURE);
}

void main(string[] args) 
{
    if (args.length != 2)
        error("É esperado um unico arquivo como argumento.");

    string arquivo = args[1];
    if (extension(arquivo) != ".hvm")
        error(format("O arquivo '%s' deve ser um arquivo harpy válido!", arquivo));

    Program prog = makeProgram(arquivo);
    HVM vm = HVM(prog.program, prog.programSize, prog.constantPool, prog.constantPoolSize);
    vm.run();

    writeln(vm.stack[0].value.i32);
}
