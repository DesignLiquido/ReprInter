module stdlib.entrada_saida;

import stdlib_base;
import core.stdc.stdio;

extern (C):

Value escreva(Params* params)
{
    Value* args = params.args;
    ulong argc = params.argc;

    if (args is null)
    {
        printf("ERRO: Args = null\n");
        return makeBool(false);
    }

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
            printf("%.8g", arg.value.f64); // %.8g remove zeros desnecessários
            break;
        case Type.Bool:
            printf("%s", arg.value.i1 ? cast(char*) "true" : cast(char*) "false");
            break;
        case Type.Array:
            printf("<Array>");
            break;
        case Type.Struct:
            printf("<Struct>");
            break;
        default:
            printf("<Unknown>");
            break;
        }
    }

    return makeBool(true);
}

Value escrevaln(Params* params)
{
    escreva(params);
    printf("\n");
    return makeBool(true);
}
