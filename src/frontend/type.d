module frontend.type;
import std.stdio : writeln;
import std.format : format;

// o sistema de tipos é simples mas poderoso
// por padrão todo tipo é uma estrutura (Type)
// o Type tem um type (tipo) que determina em sentido literal o tipo do tipo
// podendo ser um literal, indefinido, void, array e outros caso haja mais
// após isso vem o baseType (tipo base), ele determina especificamente o tipo usado em um literal ou não literal
// como é o caso do void
// sendo assim, podemos ter new Type(Types.Literal, Int) ou new Type(Types.Array, Int)
// o poder dele é justamente em tipos complexos como Array tudo ainda se manter organizado
// sendo fácil implementar ponteiros e outros
// por padrão, o new Type(Types.Array, Void) (array de tipo base Void) será um array que suporta todos os tipos
import std.algorithm : canFind;
import middle.semantic_analyzer : Symbol;

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
    Struct = "struct",
    Enum = "enum",
    Qualified = "qualified"
}

const int[string] hirarquia = [
    "logico": 1,
    "inteiro": 2,
    "decimal": 3,
];

// mapa de compatibilidade estrito
string[][string] compatibilityMap1 = [
    "inteiro": ["inteiro", "qualquer"],
    "texto": ["texto", "inteiro", "decimal", "qualquer"],
    "decimal": ["inteiro", "decimal", "qualquer"]
];

// mapa de compatibilidade liberal
string[][string] compatibilityMap2 = [
    "inteiro": ["inteiro", "decimal", "qualquer"],
    "texto": ["texto", "inteiro", "decimal", "qualquer"],
    "decimal": ["inteiro", "decimal", "qualquer"]
];

struct Type
{
    Types type;
    BaseType baseType;
    bool undefined = false;
    string structName = "";
    ulong dimensions = 0; // dimensões de um array
    string enumName = "";
    Type* next = null;

    // tipos qualificados usarão essas flags, será resolvido no analisador semantico transformando o tipo original no novo tipo resolvido
    string aliase = ""; // para tipos qualificados
    string qualified = ""; // para tipos qualificados

    bool isCompatibleWith(ref Type t, ref Symbol[string] structs, bool estrito = true)
    {
        if (baseType == BaseType.Any || t.baseType == BaseType.Any)
            return true;

        if (structName in structs)
            return true;

        // encadeado
        // se o meu next não for null
        // eu chamo o metodo de compatibilidade dele
        if (next !is null) // desreferencia os ponteiros para comparar
            if (!(*next).isCompatibleWith(t, structs))
                return false;

        // vamos supor que passou no meu next, vamos verificar se o T passado tem tambem
        if (t.next !is null)
            if (!(*t.next).isCompatibleWith(this, structs))
                return false;

        string[][string] compatibilityMap;
        if (estrito)
            compatibilityMap = compatibilityMap1;
        else
            compatibilityMap = compatibilityMap2;

        if (t.type == Types.Literal && type == Types.Literal)
            if (baseType in compatibilityMap && compatibilityMap[baseType].canFind(t.baseType))
                return true;

        if (t.enumName == enumName && t.enumName != "" && enumName != "")
            return true;

        final switch (t.type)
        {
        case Types.Literal:
            return baseType == t.baseType;
        case Types.Array:
            return type == Types.Array && t.baseType == baseType;
        case Types.Struct:
            return type == Types.Struct && t.structName == structName;
        case Types.Enum:
            return type == Types.Enum && t.enumName == enumName;
        case Types.Undefined:
            return type == Types.Undefined;
        case Types.Void:
            return type == Types.Void;
        case Types.Qualified:
            writeln("Qualificado;");
            return true;
        }
    }

    void promoteType(ref Type t)
    {
        int left = hirarquia.get(baseType, 0);
        int right = hirarquia.get(t.baseType, 0);
        // writeln("LEFT: ", baseType, " ", left);
        // writeln("RIGHT: ", t.baseType, " ", right);
        // se o nivel atual for menor que o outro nivel então haverá um "UPGRADE"
        // int < double
        // baseType = double
        // promoção do tipo mais fraco
        if (left < right)
            baseType = t.baseType;
    }

    static Type getPromotedType(ref Type left, ref Type right)
    {
        int leftLevel = hirarquia.get(left.baseType, 0);
        int rightLevel = hirarquia.get(right.baseType, 0);
        return (leftLevel >= rightLevel) ? left : right;
    }

    bool isNumeric()
    {
        return type == Types.Literal &&
            (baseType == BaseType.Int || baseType == BaseType.Double
                    || baseType == BaseType.Float || baseType == BaseType.Any);
    }

    string toStr()
    {
        string _next = "";
        if (next !is null)
            _next ~= "|" ~ (*next).toStr();
        if (type == Types.Array)
            return baseType ~ "[]" ~ _next;
        if (type == Types.Struct)
            return structName ~ _next;
        if (type == Types.Literal)
            return baseType ~ _next;
        if (type == Types.Void)
            return "void";
        if (type == Types.Qualified)
            return format("%s.%s", aliase, qualified);
        return "undefined";
    }
}
