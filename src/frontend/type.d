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

// tipo base
enum BaseType : string
{
    String = "string",

    // Numérico
    Int = "int",
    Double = "double",
    Float = "float",
    Real = "real",

    Bool = "bool",
    Void = "void",
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
            (baseType == BaseType.Int || baseType == BaseType.Double || baseType == BaseType.Float);
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
