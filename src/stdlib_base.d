module stdlib_base;

import core.stdc.stdlib : malloc, free, exit, realloc;
import core.stdc.string : memcpy, strlen, strcat, strcpy;
import core.stdc.stdio : printf, snprintf;

// contem algumas funções auxiliares que irão ajudar a desenvolver libs
// funções de conversão, validação e outros
// toda biblioteca padrão deve importar este módulo
// seria interessante todas as implementações sejam em Rust, C ou outro ter implementações semelhantes
// para manter algo padronizado

void deErro(char* fname, char* mensagem, int code = -1)
{
    printf("Erro na função '%s': %s\n", fname, mensagem);
    exit(code);
}

// função auxiliar
char* toStringz(string str)
{
    if (str.length == 0)
    {
        // Retorna string vazia
        char* empty = cast(char*) malloc(1);
        if (empty)
            empty[0] = '\0';
        return empty;
    }

    // Verifica se já é zero-terminated
    if (str.ptr[str.length] == '\0')
        return cast(char*) str.ptr;

    // Aloca memória: comprimento + terminador null
    char* result = cast(char*) malloc(str.length + 1);

    if (result is null)
        return null; // Falha na alocação

    memcpy(result, str.ptr, str.length);
    result[str.length] = '\0';

    return result;
}

// Função auxiliar para concatenar strings manualmente
char* concatenarStrings(char* s1, char* s2)
{
    if (s1 is null && s2 is null)
        return null;
    if (s1 is null)
        s1 = cast(char*) "";
    if (s2 is null)
        s2 = cast(char*) "";

    size_t len1 = strlen(s1);
    size_t len2 = strlen(s2);
    char* result = cast(char*) malloc(len1 + len2 + 1);

    if (result is null)
        return null;

    strcpy(result, s1);
    strcat(result, s2);

    return result;
}

char* tipoParaString(Type[] t)
{
    if (t.length == 0)
    {
        char* empty = cast(char*) malloc(1);
        if (empty)
            empty[0] = '\0';
        return empty;
    }

    // Começa com string vazia
    char* resultado = cast(char*) malloc(1);
    if (resultado is null)
        return null;
    resultado[0] = '\0';

    for (long i = 0; i < t.length; i++)
    {
        char* tipoAtual = tipoParaString(t[cast(ulong) i]);
        char* temp = concatenarStrings(resultado, tipoAtual);

        free(resultado);
        resultado = temp;

        if (resultado is null)
            return null;

        if ((i + 1) < t.length)
        {
            temp = concatenarStrings(resultado, cast(char*) ", ");
            free(resultado);
            resultado = temp;

            if (resultado is null)
                return null;
        }
    }

    return resultado;
}

char* tipoParaString(Type t)
{
    char* str;

    switch (t)
    {
    case Type.String:
        str = cast(char*) "texto";
        break;
    case Type.Int:
        str = cast(char*) "inteiro";
        break;
    case Type.Float:
        str = cast(char*) "decimal";
        break;
    case Type.Bool:
        str = cast(char*) "logico";
        break;
    case Type.Array:
        str = cast(char*) "array";
        break;
    case Type.Struct:
        str = cast(char*) "estrutura";
        break;
    case Type.Enum:
        str = cast(char*) "enumeracao";
        break;
    default:
        str = cast(char*) "desconhecido";
        break;
    }

    return str;
}

void verificarNumeroDeArgumentos(char* fname = cast(char*) "indefinido", ulong esperado, ulong recebido)
{
    if (esperado != recebido)
    {
        printf("A função '%s' esperava %lld argumentos mas recebeu %lld.", fname, esperado, recebido);
        exit(-1);
    }
}

void verificarNumeroDeArgumentosMinimo(char* fname, ulong esperado, ulong recebido)
{
    if (esperado > recebido)
    {
        printf("A função '%s' esperava no minimo %lld argumentos mas recebeu %lld.", fname, esperado, recebido);
        exit(-1);
    }
}

void verificarTipo(Type esperado, Type recebido)
{
    Type[1] esperado_ = [esperado];
    verificarTipo(esperado_, recebido);
}

void verificarTipo(Type[] esperados, Type recebido)
{
    bool valido = false;
    for (ulong i = 0; i < esperados.length; i++)
        if (esperados[i] == recebido)
        {
            valido = true;
            break;
        }

    if (!valido)
    {
        char* strEsperados = tipoParaString(esperados);
        char* strRecebido = tipoParaString(recebido);
        printf("Tipo inesperado: esperado '%s', recebido '%s'",
            strEsperados, strRecebido);
        free(strEsperados);
        free(strRecebido);
        exit(-1);
    }
}

bool eStruct(Value v)
{
    return v.type == Type.Struct && v.value.struct_ !is null;
}

bool eEnum(Value v)
{
    return v.type == Type.Enum && v.value.enum_ !is null;
}

void verificarNumeroDeCamposStruct(char* fname, Value v, long esperado)
{
    if (!eStruct(v))
        deErro(fname, cast(char*) "valor nao e uma estrutura");

    if (v.len != esperado)
    {
        char[256] buffer;
        snprintf(buffer.ptr, 256, "estrutura esperava %lld campos mas possui %lld", esperado, v.len);
        deErro(fname, buffer.ptr);
    }
}

Value obterCampoStruct(char* fname, Value v, long indice)
{
    if (!eStruct(v))
        deErro(fname, cast(char*) "valor nao e uma estrutura");

    if (indice < 0 || indice >= v.len)
    {
        char[256] buffer;
        snprintf(buffer.ptr, 256, "indice %lld fora dos limites (0-%lld)", indice, v.len - 1);
        deErro(fname, buffer.ptr);
    }
    return v.value.struct_[indice];
}

void verificarTipoCampoStruct(char* fname, Value v, long indice, Type esperado)
{
    Value campo = obterCampoStruct(fname, v, indice);

    if (campo.type != esperado)
    {
        char[512] buffer;
        char* strEsperado = tipoParaString(esperado);
        char* strRecebido = tipoParaString(campo.type);
        snprintf(buffer.ptr, 512, "campo %lld: esperado tipo '%s', recebido '%s'",
            indice, strEsperado, strRecebido);
        deErro(fname, buffer.ptr);
    }
}

void verificarTiposCamposStruct(char* fname, Value v, Type[] tiposEsperados)
{
    verificarNumeroDeCamposStruct(fname, v, cast(long) tiposEsperados.length);

    for (long i = 0; i < tiposEsperados.length; i++)
        verificarTipoCampoStruct(fname, v, i, tiposEsperados[i]);
}

void modificarCampoStruct(char* fname, Value* v, long indice, Value novoValor)
{
    if (!eStruct(*v))
        deErro(fname, cast(char*) "valor nao e uma estrutura");

    if (indice < 0 || indice >= v.len)
    {
        char[256] buffer;
        snprintf(buffer.ptr, 256, "indice %lld fora dos limites (0-%lld)", indice, v.len - 1);
        deErro(fname, buffer.ptr);
    }
    v.value.struct_[indice] = novoValor;
}

Value copiarStruct(Value v)
{
    if (!eStruct(v))
        return v;

    Value* novosCampos = cast(Value*) malloc(Value.sizeof * v.len);
    if (novosCampos is null)
        deErro(cast(char*) "copiarStruct", cast(char*) "falha ao alocar memoria");

    memcpy(novosCampos, v.value.struct_, Value.sizeof * v.len);
    return makeStruct(novosCampos, v.len);
}

void verificarNumeroDeVariantesEnum(char* fname, Value v, long esperado)
{
    if (!eEnum(v))
        deErro(fname, cast(char*) "valor nao e uma enumeracao");

    if (v.len != esperado)
    {
        char[256] buffer;
        snprintf(buffer.ptr, 256, "enumeracao esperava %lld variantes mas possui %lld", esperado, v
                .len);
        deErro(fname, buffer.ptr);
    }
}

long obterVarianteAtiva(char* fname, Value v)
{
    if (!eEnum(v))
        deErro(fname, cast(char*) "valor nao e uma enumeracao");

    if (v.len < 1)
        deErro(fname, cast(char*) "enumeracao invalida: sem campos");

    Value tag = v.value.enum_[0];
    if (tag.type != Type.Int)
        deErro(fname, cast(char*) "enumeracao invalida: tag nao e inteiro");

    return tag.value.i64;
}

Value obterDadosVariante(char* fname, Value v, long varianteEsperada)
{
    long varianteAtiva = obterVarianteAtiva(fname, v);

    if (varianteAtiva != varianteEsperada)
    {
        char[256] buffer;
        snprintf(buffer.ptr, 256, "variante incorreta: esperado %lld, ativo %lld",
            varianteEsperada, varianteAtiva);
        deErro(fname, buffer.ptr);
    }

    if (v.len < 2)
        deErro(fname, cast(char*) "enumeracao sem dados");

    return v.value.enum_[1];
}

bool eVariante(Value v, long variante)
{
    if (!eEnum(v) || v.len < 1)
        return false;

    Value tag = v.value.enum_[0];
    if (tag.type != Type.Int)
        return false;

    return tag.value.i64 == variante;
}

void liberarStruct(Value* v)
{
    if (eStruct(*v) && v.value.struct_ !is null)
    {
        free(v.value.struct_);
        v.value.struct_ = null;
        v.len = 0;
    }
}

void liberarEnum(Value* v)
{
    if (eEnum(*v) && v.value.enum_ !is null)
    {
        free(v.value.enum_);
        v.value.enum_ = null;
        v.len = 0;
    }
}

union RawValue
{
    char* str;
    long i64;
    double f64;
    bool i1;
    Value* array;
    Value* struct_;
    Value* enum_;
}

enum Type
{
    String,
    Int,
    Float,
    Bool,
    Array,
    Struct,
    Enum
}

struct Value
{
    Type type;
    RawValue value;
    long len;
}

struct Params
{
    Value* args;
    ulong argc;
}

pragma(inline, true)
Value makeInt(long i)
{
    RawValue ev;
    ev.i64 = i;
    return Value(Type.Int, ev);
}

pragma(inline, true)
Value makeStr(string s)
{
    RawValue ev;
    ev.str = cast(char*) s;
    return Value(Type.String, ev);
}

pragma(inline, true)
Value makeStr(char* s)
{
    RawValue ev;

    // duplica a string para ter controle total
    // o ponteiro original será liberado logo após essa chamada
    if (s !is null)
    {
        size_t len = strlen(s);
        char* copia = cast(char*) malloc(len + 1);
        if (copia is null)
            deErro(cast(char*) "makeStr", cast(char*) "falha ao alocar memoria");
        memcpy(copia, s, len + 1);
        ev.str = copia;
    }
    else
        ev.str = null;

    return Value(Type.String, ev);
}

pragma(inline, true)
Value makeFloat(double f)
{
    RawValue ev;
    ev.f64 = f;
    return Value(Type.Float, ev);
}

pragma(inline, true)
Value makeBool(bool b)
{
    RawValue ev;
    ev.i1 = b;
    return Value(Type.Bool, ev);
}

pragma(inline, true)
Value makeStruct(Value* values, long tamanho)
{
    RawValue ev;
    ev.struct_ = values;
    return Value(Type.Struct, ev, tamanho);
}

pragma(inline, true)
Value makeEnum(Value* values, long tamanho)
{
    RawValue ev;
    ev.enum_ = values;
    return Value(Type.Enum, ev, tamanho);
}

void liberarValue(Value* v)
{
    if (v.type == Type.String && v.value.str !is null)
    {
        free(v.value.str);
        v.value.str = null;
    }
    else if (v.type == Type.Struct)
        liberarStruct(v);
    else if (v.type == Type.Enum)
        liberarEnum(v);
}
