module stdlib.arquivo;

import stdlib_base;
import core.stdc.stdio;
import core.stdc.string;
import core.stdc.stdlib;

extern (C):

Value lerArquivo(Params* params)
{
    Value* args = params.args;
    ulong argc = params.argc;
    verificarNumeroDeArgumentos(cast(char*) "lerArquivo", 1, argc);

    Value fileName = args[0];
    verificarTipo(Type.String, fileName.type);

    Value* structValues = cast(Value*) malloc(3 * Value.sizeof);
    if (structValues is null)
    {
        return makeStruct(null, 0);
    }

    const char* path = fileName.value.str;
    FILE* file = fopen(path, "rb");
    if (file is null)
    {
        structValues[0] = makeStr(cast(char*) "Falha ao abrir o arquivo.");
        structValues[1] = makeInt(0);
        structValues[2] = makeInt(1);
        return makeStruct(structValues, 3);
    }

    fseek(file, 0, SEEK_END);
    long size = ftell(file);
    rewind(file);

    char* buffer = cast(char*) malloc(size + 1);
    if (buffer is null)
    {
        fclose(file);
        structValues[0] = makeStr(cast(char*) "Falha ao alocar memoria");
        structValues[1] = makeInt(0);
        structValues[2] = makeInt(1);
        return makeStruct(structValues, 3);
    }

    size_t lidos = fread(buffer, 1, size, file);
    buffer[lidos] = '\0';
    fclose(file);

    structValues[0] = makeStr(buffer);
    structValues[1] = makeInt(size);
    structValues[2] = makeInt(0);

    return makeStruct(structValues, 3);
}
