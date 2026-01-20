import std.json, std.stdio, std.conv, std.traits, std.range, std.algorithm, std.file;

const string APP = "harpy.json";

struct Compilacao
{
    string saida;
    bool estatico;
    bool biblioteca_nativa;
    bool otimizar;
}

struct ProjetoConfig
{
    string nome;
    string descricao;
    string autor;
    string versao;
    string entrada;
    Compilacao compilacao;
    string[] dependencias;
}

private T getConfig(T)(JSONValue json, string key, T defaultValue = T.init)
{
    // Verifica se a chave existe
    if (key !in json.object)
        return defaultValue;

    JSONValue value = json[key];

    // String
    static if (is(T == string))
    {
        if (value.type != JSONType.string)
            return defaultValue;
        return value.str;
    }
    // Bool
    else static if (is(T == bool))
    {
        if (value.type != JSONType.true_ && value.type != JSONType.false_)
            return defaultValue;
        return value.boolean;
    }
    // Inteiros
    else static if (isIntegral!T)
    {
        if (value.type != JSONType.integer && value.type != JSONType.uinteger)
            return defaultValue;
        try
            return to!T(value.integer);
        catch (Exception e)
            return defaultValue;
    }
    // Floats
    else static if (isFloatingPoint!T)
    {
        if (value.type == JSONType.float_)
            return to!T(value.floating);
        else if (value.type == JSONType.integer || value.type == JSONType.uinteger)
            return to!T(value.integer);
        return defaultValue;
    }
    // Arrays
    else static if (isArray!T && !is(T == string))
    {
        alias ElementType = ForeachType!T;

        if (value.type != JSONType.array)
            return defaultValue;

        T result;
        foreach (item; value.array)
        {
            try
                result ~= jsonToValue!ElementType(item);
            catch (Exception e) // Ignora elementos inválidos
                continue;
        }
        return result;
    }
    // Associative Arrays (dicionários)
    else static if (isAssociativeArray!T)
    {
        alias K = KeyType!T;
        alias V = ValueType!T;

        static assert(is(K == string), "Chaves de AA devem ser strings");

        if (value.type != JSONType.object)
            return defaultValue;

        T result;
        foreach (k, v; value.object)
        {
            try
                result[k] = jsonToValue!V(v);
            catch (Exception e)
                continue;
        }
        return result;
    }
    // Structs
    else static if (is(T == struct))
    {
        if (value.type != JSONType.object)
            return defaultValue;

        T result;
        foreach (i, field; result.tupleof)
        {
            enum fieldName = __traits(identifier, result.tupleof[i]);
            if (fieldName in value.object)
            {
                try
                    result.tupleof[i] = jsonToValue!(typeof(field))(value[fieldName]);
                catch (Exception e)
                {
                    // Mantém valor padrão do campo
                }
            }
        }
        return result;
    }
    else
        static assert(0, "Tipo não suportado: " ~ T.stringof);
}

private T jsonToValue(T)(JSONValue value)
{
    static if (is(T == string))
        return value.str;
    else static if (is(T == bool))
        return value.boolean;
    else static if (isIntegral!T)
        return to!T(value.integer);
    else static if (isFloatingPoint!T)
    {
        if (value.type == JSONType.float_)
            return to!T(value.floating);
        else
            return to!T(value.integer);
    }
    else static if (isArray!T && !is(T == string))
    {
        alias ElementType = ForeachType!T;
        T result;
        foreach (item; value.array)
            result ~= jsonToValue!ElementType(item);
        return result;
    }
    else static if (isAssociativeArray!T)
    {
        alias ValueType = ValueType!T;
        T result;
        foreach (k, v; value.object)
            result[k] = jsonToValue!ValueType(v);
        return result;
    }
    else static if (is(T == struct))
    {
        T result;
        foreach (i, field; result.tupleof)
        {
            enum fieldName = __traits(identifier, result.tupleof[i]);
            if (fieldName in value.object)
                result.tupleof[i] = jsonToValue!(typeof(field))(value[fieldName]);
        }
        return result;
    }
    else
        static assert(0, "Tipo não suportado: " ~ T.stringof);
}

ProjetoConfig carregarConfig()
{
    ProjetoConfig config;

    // verifica se o arquivo existe
    if (!exists(APP))
        return config;

    string json = readText(APP);
    JSONValue j = parseJSON(json);

    config.nome = j.getConfig!string("nome", "Aplicativo");
    config.descricao = j.getConfig!string("descricao", "Um aplicativo Harpy");
    config.autor = j.getConfig!string("autor", "Ninguem");
    config.entrada = j.getConfig!string("entrada", "");
    config.versao = j.getConfig!string("versao", "0.1.0");
    config.compilacao = j.getConfig!Compilacao("compilacao", Compilacao.init);
    config.dependencias = j.getConfig!(string[])("dependencias", []);

    return config;
}
