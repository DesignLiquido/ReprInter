module frontend.type;

// o sistema de tipos é simples mas poderoso
// por padrão todo tipo é uma estrutura (Type)
// o Type tem um type (tipo) que determina em sentido literal o tipo do tipo
// podendo ser um literal, indefinido, void, array e outros caso haja mais
// após isso vem o baseType (tipo base), ele determina especificamente o tipo usado em um literal ou não literal
// como é o caso do void
// sendo assim, podemos ter Type(Types.Literal, Int) ou Type(Types.Array, Int)
// o poder dele é justamente em tipos complexos como Array tudo ainda se manter organizado
// sendo fácil implementar ponteiros e outros
// por padrão, o Type(Types.Array, Void) (array de tipo base Void) será um array que suporta todos os tipos
import std.algorithm : canFind;

// tipo base
enum BaseType : string
{
    String = "texto",

    // Numérico
    Int = "inteiro",
    Double = "decimal",
    Float = "f32",
    Real = "f128",

    Bool = "logico",
    Void = "vazio",
    Any = "qualquer",
}

// tipos que um Type pode ter
enum Types : string
{
    Literal = "literal", // string, int, void, ...
    Undefined = "undefined", // tipo que deve ser resolvido pelo analisador semantico
    Void = "void", // é um tipo não literal
    Array = "array",
}

struct Type
{
    Types type;
    BaseType baseType;
    bool undefined = false;
    ulong dimensions = 0; // dimensões de um array

    bool isCompatibleWith(Type t)
    {
        if (baseType == BaseType.Any || t.baseType == BaseType.Any)
            return true;

        // mapa de compatibilidade
        string[][string] compatibilityMap = [
            "inteiro": ["inteiro", "decimal", "qualquer"],
            "texto": ["texto", "qualquer"],
            "decimal": ["inteiro", "decimal", "qualquer"]
        ];

        if (toStr() in compatibilityMap && compatibilityMap[toStr()].canFind(t.toStr()))
            return true;

        final switch (t.type)
        {
        case Types.Literal:
            return baseType == t.baseType;
        case Types.Array:
            return type == Types.Array && t.baseType == baseType;
        case Types.Undefined:
            return type == Types.Undefined;
        case Types.Void:
            return type == Types.Void;
        }
    }

    bool isNumeric()
    {
        return type == Types.Literal &&
            (baseType == BaseType.Int || baseType == BaseType.Double
                    || baseType == BaseType.Float || baseType == BaseType.Any);
    }

    string toStr()
    {
        if (type == Types.Array)
            return baseType ~ "[]";
        if (type == Types.Literal)
            return baseType;
        if (type == Types.Void)
            return "void";
        return "undefined";
    }
}
