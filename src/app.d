module app;

import harpyvm;
import core.stdc.stdio, core.stdc.string;
import core.stdc.stdlib : exit, EXIT_FAILURE, free, malloc;

@nogc:
extern(C):

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

long size(FILE* f)
{
    if (f is null) return -1;
    fseek(f, 0, SEEK_END);
    long tamanho = ftell(f);
    fseek(f, 0, SEEK_SET);
    return tamanho;
}

Program makeProgram(char* filename)
{
    Program p;
    FILE* f = fopen(filename, "rb");
    if (f.size() < TAMANHO_MINIMO)
        error("O arquivo não pode ser um programa harpy válido!");
    
    ubyte[19] NM = cast(ubyte[])NUMERO_MAGICO;
    ubyte[19] mn;
    fread(mn.ptr, ubyte.sizeof, 19, f);
    if (mn != NM)
        error("O número mágico (MAGIC NUMBER) do programa é inválido.");

    // no futuro poderá haver mais versões do bytecode
    // vou deixar um erro aqui por padrão na primeira versão de todas
    ubyte[1] versao;
    fread(versao.ptr, ubyte.sizeof, 1, f);
    if (versao[0] != VERSAO)
        error("A versão do programa não é válida.");
    
    uint[2] progPoolBuff;
    fread(progPoolBuff.ptr, uint.sizeof, 2, f);
    // pode ter ocorrido um erro ao ler
    uint progSize = progPoolBuff[0];
    if (progSize < 0 || progSize == uint.max)
        error("Erro ao ler o tamanho do programa.");
    
    uint poolSize = progPoolBuff[1];
    if (poolSize < 0 || poolSize == uint.max)
        error("Erro ao ler o tamanho do mapa de constantes.");
    
    uint* program = cast(uint*) malloc(progSize * uint.sizeof);
    if (program is null)
        error("Ocorreu um erro ao alocar memória pro programa.");
    
    HVMValue* constantPool = cast(HVMValue*) malloc(poolSize * HVMValue.sizeof);
    if (constantPool is null)
    {
        if (program !is null) free(program); // libera o programa alocado
        error("Ocorreu um erro ao alocar memória pro mapa de constantes.");
    }

    if (progSize > 0)
        fread(program, uint.sizeof, progSize, f);
    
    if (poolSize > 0)
    {
        // carregar os valores para a memoria é um pouco mais complexo
        // cada valor tem que ter o tipo respeitado e outras questões
        uint idx;
        for (uint i; i < poolSize; i++)
        {
            // todo valor tem o tipo como primeiro valor passado
            ubyte[1] tipo;
            fread(tipo.ptr, ubyte.sizeof, 1, f);
            bool   bo;
            byte   by;
            ubyte  uby;
            char   ch;
            short  sh;
            ushort ush;
            int    it;
            uint   uit;
            long   l;
            ulong  ul;
            float  fl;
            double dl;
            switch (tipo[0]) {
                case HVMType.Bool:   fread(&bo,  1, 1, f);  constantPool[idx++] = HVMValue.makeBool(bo);    continue;
                case HVMType.Byte:   fread(&by,  1, 1, f);  constantPool[idx++] = HVMValue.makeByte(by);    continue;
                case HVMType.Ubyte:  fread(&uby, 1, 1, f);  constantPool[idx++] = HVMValue.makeUbyte(uby);  continue;
                case HVMType.Char:   fread(&ch,  1, 1, f);  constantPool[idx++] = HVMValue.makeChar(ch);    continue;
                case HVMType.Short:  fread(&sh,  2, 1, f);  constantPool[idx++] = HVMValue.makeShort(sh);   continue;
                case HVMType.Ushort: fread(&ush, 2, 1, f);  constantPool[idx++] = HVMValue.makeUshort(ush); continue;
                case HVMType.Int:    fread(&it,  4, 1, f);  constantPool[idx++] = HVMValue.makeInt(it);     continue;
                case HVMType.Uint:   fread(&uit, 4, 1, f);  constantPool[idx++] = HVMValue.makeUint(uit);   continue;
                case HVMType.Long:   fread(&l,   8, 1, f);  constantPool[idx++] = HVMValue.makeLong(l);     continue;
                case HVMType.Ulong:  fread(&ul,  8, 1, f);  constantPool[idx++] = HVMValue.makeUlong(ul);   continue;
                case HVMType.Float:  fread(&fl,  4, 1, f);  constantPool[idx++] = HVMValue.makeFloat(fl);   continue;
                case HVMType.Double: fread(&dl,  8, 1, f);  constantPool[idx++] = HVMValue.makeDouble(dl);  continue;
                default:
                    printf("Tipo: %u\n", tipo[0]);
                    error("Tipo desconhecido.");
                    break;
            }
        }
    }

    fclose(f);

    p.constantPool = constantPool;
    p.constantPoolSize = poolSize;
    p.program = program;
    p.programSize = progSize;

    return p;
}

void error(string msg)
{
    printf(cast(char*)"Erro: %s\n", cast(char*)msg);
    exit(EXIT_FAILURE);
}

void main(int argc, char** args) 
{
    if (argc != 2)
        error("É esperado um unico arquivo como argumento.");

    char* arquivo = args[1];
    long len = strlen(arquivo);
    if (len < 4)
        error("O arquivo deve ser um arquivo harpy válido!");

    char* ext = cast(char*)arquivo[len-3..len-1];
    if (strcmp(ext, "hvm") != 0)
        error("O arquivo deve ser um arquivo harpy válido!");

    Program prog = makeProgram(arquivo);
    HVM vm = HVM(prog.program, prog.programSize, prog.constantPool, prog.constantPoolSize);
    vm.run();

    printf("Result: %d\n", vm.stack[0].value.i32);
}
