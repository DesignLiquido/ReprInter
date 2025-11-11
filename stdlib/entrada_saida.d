module stdlib.entrada_saida;

import stdlib_base;
import core.stdc.stdio, core.stdc.string, core.stdc.stdlib;

extern (C):

Value escreva(Params* params)
{
    Value* args = params.args;
    ulong argc = params.argc;
    verificarNumeroDeArgumentosMinimo(cast(char*) "escreva", 1, argc);

    for (ulong i; i < argc; i++)
    {
        Value arg = args[i];

        switch (arg.type)
        {
        case Type.String:
            printf("%s", arg.value.str);
            break;
        case Type.Int:
            printf("%lld", arg.value.i64);
            break;
        case Type.Float:
            printf("%.8f", arg.value.f64);
            break;
        case Type.Bool:
            printf("%s", arg.value.i1 ? cast(char*) "verdadeiro" : cast(char*) "falso");
            break;
        case Type.Array:
            printf("<Array>");
            break;
        case Type.Struct:
            printf("<Estrutura>");
            break;
        default:
            printf("<Desconhecido>");
            break;
        }
    }

    return makeBool(true);
}

Value escrevaln(Params* params)
{
    verificarNumeroDeArgumentosMinimo(cast(char*) "escrevaln", 1, params.argc);
    escreva(params);
    printf("\n");
    return makeBool(true);
}

Value escrevaf(Params* params)
{
    Value* args = params.args;
    ulong argc = params.argc;
    verificarNumeroDeArgumentosMinimo(cast(char*) "escrevaf", 1, argc);

    char* message = args[0].value.str;
    size_t argI = 1;
    size_t messageLen = strlen(message);

    for (size_t i = 0; i < messageLen; i++)
    {
        char ch = message[i];

        if (ch == '%')
        {
            if (i + 1 >= messageLen)
                deErro(cast(char*) "escrevaf", cast(char*) "Formato inválido: '%' no final da string");

            i++;
            ch = message[i];

            if (ch == '%')
            {
                putchar('%');
                continue;
            }

            // Validar se há argumentos suficientes
            if (argI >= argc)
                deErro(
                    cast(char*) "escrevaf", cast(char*) "Argumentos insuficientes para os especificadores de formato"
                );

            switch (ch)
            {
            case 's':
                if (args[argI].type != Type.String)
                    deErro(cast(char*) "escrevaf", cast(char*) "Esperado tipo String para %s");
                printf("%s", args[argI].value.str);
                argI++;
                break;

            case 'd':
                if (args[argI].type != Type.Int)
                    deErro(cast(char*) "escrevaf", cast(char*) "Esperado tipo Int para %d");
                printf("%lld", args[argI].value.i64);
                argI++;
                break;

            case 'f':
                if (args[argI].type != Type.Float)
                    deErro(cast(char*) "escrevaf", cast(char*) "Esperado tipo Float para %f");
                printf("%.8g", args[argI].value.f64);
                argI++;
                break;

            case 'b':
                if (args[argI].type != Type.Bool)
                    deErro(cast(char*) "escrevaf", cast(char*) "Esperado tipo Bool para %b");
                printf("%s", args[argI].value.i1 ? cast(char*) "verdadeiro" : cast(char*) "falso");
                argI++;
                break;

            default:
                char[100] errorMsg;
                snprintf(errorMsg.ptr, 100, "Especificador de formato inválido: '%%%c'", ch);
                deErro(cast(char*) "escrevaf", errorMsg.ptr);
            }
        }
        else if (ch == '\\')
        {
            if (i + 1 >= messageLen)
                deErro(cast(char*) "escrevaf", cast(char*) "Escape inválido: '\\' no final da string");

            i++;
            ch = message[i];

            switch (ch)
            {
            case '\\':
                putchar('\\');
                break;
            case 'n':
                putchar('\n');
                break;
            case 't':
                putchar('\t');
                break;
            case 'r':
                putchar('\r');
                break;
            case '"':
                putchar('"');
                break;
            case '\'':
                putchar('\'');
                break;
            default:
                char[100] errorMsg;
                snprintf(errorMsg.ptr, 100, "Sequência de escape inválida: '\\%c'", ch);
                deErro(cast(char*) "escrevaf", errorMsg.ptr);
            }
        }
        else
            putchar(ch);
    }

    return makeBool(true);
}

Value entrada(Params* params)
{
    Value* args = params.args;
    ulong argc = params.argc;

    if (argc >= 1)
    {
        verificarTipo(Type.String, args[0].type);
        printf("%s", args[0].value.str);
        fflush(stdout);
    }

    size_t bufferSize = 256;
    char* buffer = cast(char*) malloc(bufferSize);

    if (buffer is null)
        deErro(cast(char*) "entrada", cast(char*) "falha ao alocar memoria");

    size_t pos = 0;
    int c;

    while ((c = getchar()) != '\n' && c != EOF)
    {
        if (pos >= bufferSize - 1)
        {
            bufferSize *= 2;
            char* newBuffer = cast(char*) realloc(buffer, bufferSize);

            if (newBuffer is null)
            {
                free(buffer);
                deErro(cast(char*) "entrada", cast(char*) "falha ao realocar memoria");
            }

            buffer = newBuffer;
        }

        buffer[pos++] = cast(char) c;
    }

    buffer[pos] = '\0';

    if (pos + 1 < bufferSize)
    {
        char* finalBuffer = cast(char*) realloc(buffer, pos + 1);
        if (finalBuffer !is null)
            buffer = finalBuffer;
    }

    Value resultado = makeStr(buffer);
    free(buffer);
    return resultado;
}
