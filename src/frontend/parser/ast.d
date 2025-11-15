module frontend.parser.ast;

import std.stdio, std.variant, std.format, std.conv, std.string, std.array;
import frontend.type, frontend.lexer.token : Loc;

// tipo de um nó (node)
enum NodeKind
{
    Program,
    Identifier,
    IfStatement,
    ElseStatement,
    ForStatement,
    Return,
    Extern,
    BreakOrContinueStmt,
    WhileStatement,
    ImportStatement,

    // literais
    IntLiteral,
    StringLiteral,
    DoubleLiteral,
    BoolLiteral,
    ArrayLiteral,

    // declarações
    FuncDeclaration,
    VarDeclaration,
    VarAssignmentDecl,
    StructDeclaration,
    MemberCallAssignmentDecl,
    IndexAssignmentDecl,
    EnumDeclaration,
    ConstDeclaration,

    // expressões
    BinaryExpr,
    CallExpr,
    UnaryExpr,
    StructExpr,
    MemberCallExpr,
    IndexExpr,

    EoP, // End of Program (fim do programa)
}

// classe abstrata que define como os nós (nodes) devem ser
abstract class Node
{
    NodeKind kind;
    Variant value;
    Type type;
    Loc loc;
    bool publico = false;
    string nameMangling = "main";

    void print(ulong ident = 0, bool isLast = false);
}

class Program : Node
{
    Node[] body;
    this(Node[] body)
    {
        this.kind = NodeKind.Program;
        this.type = Type(Types.Literal, BaseType.Int);
        this.body = body;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        println("├── Programa", ident);
        println("│   ├── Tipo: " ~ cast(string) type.baseType, ident);
        println("│   └── Corpo (" ~ to!string(body.length) ~ " nó(s)):", ident);
        foreach (long i, Node node; body)
        {
            if (i == cast(uint)
                body.length - 1)
                node.print(ident + 8, true); // ultimo
            else
                node.print(ident + 8, false);
        }
    }
}

struct FunctionArgument
{
    string name;
    Type type;
    Node value;
    bool defaultValue;
    bool isRef;
    Loc loc;
}

class FunctionDeclaration : Node
{
    string name;
    Node[] body;
    FunctionArgument[] args;
    bool externo = false;
    this(string name, ref FunctionArgument[] args, Node[] body, Type type, Loc loc, bool externo, bool publico = false)
    {
        this.kind = NodeKind.FuncDeclaration;
        this.type = type;
        this.body = body;
        this.name = name;
        this.args = args;
        this.externo = externo;
        this.publico = publico;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "FunctionDeclaration: " ~ name, ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "├── Argumentos (" ~ to!string(args.length) ~ "):", ident);

        foreach (long i, FunctionArgument arg; args)
        {
            string argPrefix = (i == cast(uint) args.length - 1) ? "└── " : "├── ";
            println(continuation ~ "│   " ~ argPrefix ~ "Argumento: " ~ arg.name, ident);
            println(continuation ~ "│   " ~ (i == cast(uint) args.length - 1 ? "    " : "│   ") ~
                    "├── Tipo: " ~ cast(string) arg.type.baseType, ident);
            println(continuation ~ "│   " ~ (i == cast(uint) args.length - 1 ? "    " : "│   ") ~
                    "└── Tem valor padrão: " ~ to!string(arg.defaultValue), ident);
        }

        println(continuation ~ "└── Corpo (" ~ to!string(body.length) ~ " nó(s)):", ident);
        foreach (long i, Node node; body)
        {
            if (i == cast(uint)
                body.length - 1)
                node.print(ident + continuation.length + 4, true);
            else
                node.print(ident + continuation.length + 4, false);
        }
    }
}

// Identificador (a-z, A-Z, _, 0-9)
class Identifier : Node
{
    this(string id, Loc loc)
    {
        this.kind = NodeKind.Identifier;
        this.type = Type(Types.Undefined, BaseType.Void);
        this.value = id;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "Identifier: " ~ value.get!string, ident);
        println(continuation ~ "└── Tipo: " ~ cast(string) type.baseType, ident);
    }
}

// Declaração de Variavel
class VarDeclaration : Node
{
    string id;
    this(string id, Type type, Node value, Loc loc)
    {
        this.kind = NodeKind.VarDeclaration;
        this.id = id;
        this.type = type;
        this.value = value;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "VarDeclaration: " ~ id, ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "└── Valor:", ident);
        value.get!Node.print(ident + continuation.length + 4, true);
    }
}

class VarAssignmentDecl : Node
{
    string id;
    this(string id, Type type, Node value, Loc loc)
    {
        this.kind = NodeKind.VarAssignmentDecl;
        this.id = id;
        this.type = type;
        this.value = value;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "VarAssignmentDecl: " ~ id, ident);
        println(continuation ~ "├── Type: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "└── Value:", ident);
        value.get!Node.print(ident + continuation.length + 4, true);
    }
}

// Literais {{

// literal de um dec (decimal de 64 bits)
class DoubleLiteral : Node
{
    this(double n, Loc loc)
    {
        this.kind = NodeKind.DoubleLiteral;
        this.type = Type(Types.Literal, BaseType.Double);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "DoubleLiteral: " ~ to!string(value.get!double), ident);
        println(continuation ~ "└── Tipo: " ~ cast(string) type.baseType, ident);
    }
}

// literal de um int (inteiro)
class IntLiteral : Node
{
    this(long n, Loc loc)
    {
        this.kind = NodeKind.IntLiteral;
        this.type = Type(Types.Literal, BaseType.Int);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "IntLiteral: " ~ to!string(value.get!long), ident);
        println(continuation ~ "└── Tipo: " ~ cast(string) type.baseType, ident);
    }
}

// literal de uma string (texto)
class StringLiteral : Node
{
    this(string n, Loc loc)
    {
        this.kind = NodeKind.StringLiteral;
        this.type = Type(Types.Literal, BaseType.String);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "StringLiteral: \"" ~ value.get!string ~ "\"", ident);
        println(continuation ~ "└── Tipo: " ~ cast(string) type.baseType, ident);
    }
}

class BoolLiteral : Node
{
    this(bool n, Loc loc)
    {
        this.kind = NodeKind.BoolLiteral;
        this.type = Type(Types.Literal, BaseType.Bool);
        this.value = n;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "BoolLiteral: " ~ value.get!bool ? "verdadeiro" : "falso", ident);
        println(continuation ~ "└── Tipo: " ~ cast(string) type.baseType, ident);
    }
}

// }}

class CallExpr : Node
{
    string id;
    Node[] args;
    this(string id, Node[] args, Loc loc)
    {
        this.kind = NodeKind.CallExpr;
        this.type = Type(Types.Undefined, BaseType.Void);
        this.id = id;
        this.loc = loc;
        this.args = args;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "CallExpr: " ~ id ~ "()", ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "└── Argumentos (" ~ to!string(args.length) ~ "):", ident);

        foreach (long i, Node arg; args)
        {
            if (i == cast(uint) args.length - 1)
                arg.print(ident + continuation.length + 4, true);
            else
                arg.print(ident + continuation.length + 4, false);
        }
    }
}

// Expressão Binaria (1+1 ....)
class BinaryExpr : Node
{
    Node left, right;
    string op;
    this(Node left, Node right, string op, Loc loc)
    {
        this.kind = NodeKind.BinaryExpr;
        this.type = left.type;
        this.left = left;
        this.loc = loc;
        this.right = right;
        this.op = op;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "BinaryExpr: (" ~ op ~ ")", ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "├── Esquerda:", ident);

        if (left !is null)
            left.print(ident + continuation.length + 4, false);
        else
            println(continuation ~ "│   └── (nulo)", ident);

        println(continuation ~ "└── Direita:", ident);

        if (right !is null)
            right.print(ident + continuation.length + 4, true);
        else
            println(continuation ~ "    └── (nulo)", ident);
    }
}

// Expressão Unaria => 1 - -10 (11)
class UnaryExpr : Node
{
    string op; // "-", "!", "+"
    Node operand;
    // define se o operador veio antes ou após a exressão
    // i++ = true
    // ++i = false
    bool postFix;

    this(string op, Node operand, Loc loc, bool postFix = false)
    {
        this.kind = NodeKind.UnaryExpr;
        this.op = op;
        this.postFix = postFix;
        this.operand = operand;
        this.type = Type(Types.Void, BaseType.Void);
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "UnaryExpr", ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "├── Operador: " ~ op, ident);
        println(continuation ~ "├── PostFix: " ~ (postFix ? "sim" : "não"), ident);

        if (operand !is null)
        {
            println(continuation ~ "└── Operando:", ident);
            operand.print(ident + continuation.length + 4, true);
        }
        else
            println(continuation ~ "└── Operando: nulo", ident);
    }
}

class IfStatement : Node
{
    Node condition;
    Node[] body;
    Node else_;
    this(Node condition, Node[] body, Type type, Node else_ = null, Loc loc)
    {
        this.kind = NodeKind.IfStatement;
        this.type = type;
        this.condition = condition;
        this.body = body;
        this.loc = loc;
        this.else_ = else_;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "IfStatement", ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "├── Condição:", ident);

        if (condition !is null)
            condition.print(ident + continuation.length + 4, false);
        else
            println(continuation ~ "│   └── (nulo)", ident);

        println(continuation ~ "└── Corpo (" ~ to!string(body.length) ~ " nó(s)):", ident);
        foreach (long i, Node node; body)
        {
            if (i == cast(uint)
                body.length - 1)
                node.print(ident + continuation.length + 4, else_ !is null);
            else
                node.print(ident + continuation.length + 4, false);
        }

        if (else_ !is null)
        {
            println(continuation ~ "└── Else:", ident);
            else_.print(ident + continuation.length + 4, true);
        }
    }
}

class ElseStatement : Node
{
    Node[] body;
    this(Node[] body = [], Type type, Loc loc)
    {
        this.kind = NodeKind.ElseStatement;
        this.type = type;
        this.loc = loc;
        this.body = body;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "ElseStatement", ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);

        println(continuation ~ "└── Corpo (" ~ to!string(body.length) ~ " nó(s)):", ident);
        foreach (long i, Node node; body)
            node.print(ident + continuation.length + 4, false);
    }
}

class Return : Node
{
    bool ret;
    this(Node expr, bool ret = true, Loc loc)
    {
        this.kind = NodeKind.Return;
        this.type = expr ? expr.type : Type.init;
        this.value = expr;
        this.loc = loc;
        this.ret = ret;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "Return" ~ (ret ? "" : " (vazio)"), ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "└── Expressão:", ident);

        if (value.convertsTo!Node && !value.hasValue())
            value.get!Node.print(ident + continuation.length + 4, true);
        else
            println(continuation ~ "    └── (nulo)", ident);
    }
}

class ForStatement : Node
{
    Node init_;
    Node condition;
    Node increment;
    Node[] body;

    this(Node init_, Node condition, Node increment, Node[] body, Loc loc)
    {
        this.kind = NodeKind.ForStatement;
        this.type = Type(Types.Void, BaseType.Void);
        this.init_ = init_;
        this.condition = condition;
        this.increment = increment;
        this.body = body;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "ForStatement", ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);

        // inicialização
        println(continuation ~ "├── Inicialização:", ident);
        if (init_ !is null)
            init_.print(ident + continuation.length + 4, false);
        else
            println(continuation ~ "│   └── (nulo)", ident);

        // condição
        println(continuation ~ "├── Condição:", ident);
        if (condition !is null)
            condition.print(ident + continuation.length + 4, false);
        else
            println(continuation ~ "│   └── (nulo)", ident);

        // incremento
        println(continuation ~ "├── Incremento:", ident);
        if (increment !is null)
            increment.print(ident + continuation.length + 4, false);
        else
            println(continuation ~ "│   └── (nulo)", ident);

        // corpo
        println(continuation ~ "└── Corpo (" ~ to!string(body.length) ~ " nó(s)):", ident);
        foreach (long i, Node node; body)
            if (i == cast(uint)
                body.length - 1)
                node.print(ident + continuation.length + 4, true);
            else
                node.print(ident + continuation.length + 4, false);
    }
}

struct StructField
{
    string name;
    Type type;
    bool defaultValue = false;
    Node value = null;
}

class StructDeclaration : Node
{
    string name;
    StructField[] fields;
    this(string name, ref StructField[] fields, Loc loc, bool publico = false)
    {
        this.publico = publico;
        this.kind = NodeKind.StructDeclaration;
        this.fields = fields;
        this.name = name;
        this.loc = loc;
        this.type = Type(Types.Struct, BaseType.Void);
        this.type.structName = name;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        // ...
    }
}

class StructExpr : Node
{
    string name;
    Node[] fields;
    this(CallExpr node)
    {
        this.kind = NodeKind.StructExpr;
        this.fields = node.args;
        this.name = node.id;
        this.loc = node.loc;
        this.type = node.type;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        // ...
    }
}

class Extern : Node
{
    FunctionDeclaration[] funcs;
    this(FunctionDeclaration[] funcs, Loc loc)
    {
        this.kind = NodeKind.Extern;
        this.type = Type(Types.Void, BaseType.Void);
        this.funcs = funcs;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        // ...
    }
}

class MemberCallExpr : Node
{
    Node object; // A expressão à esquerda do ponto (Estrutura.campo) -> Estrutura
    Identifier member; // O membro sendo chamado
    ulong fieldIdx = 0; // posição do field (campo) em relação a struct
    Node[] args; // Argumentos se for uma chamada de método
    bool isMethodCall; // true se for x.method(), false se for x.property

    this(Node object, Identifier member, Node[] args, bool isMethodCall, Loc loc)
    {
        this.kind = NodeKind.MemberCallExpr;
        this.object = object;
        this.member = member;
        this.args = args;
        this.isMethodCall = isMethodCall;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        // ...
    }
}

class MemberCallAssignmentDecl : Node
{
    MemberCallExpr member; // A expressão à esquerda do ponto (Estrutura.campo) -> Estrutura

    this(MemberCallExpr member, Node value, Loc loc)
    {
        this.kind = NodeKind.MemberCallAssignmentDecl;
        this.member = member;
        this.value = value;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        // ...
    }
}

class ArrayLiteral : Node
{
    this(Node[] value, Type type, Loc loc)
    {
        this.kind = NodeKind.ArrayLiteral;
        this.type = type;
        this.value = value;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "ArrayLiteral: ", ident);
        println(continuation ~ "└── Type: " ~ cast(string) type.baseType ~ "[]", ident);
    }
}

class IndexExpr : Node
{
    Node idx, object;
    this(Node object, Node idx, Loc loc)
    {
        this.kind = NodeKind.IndexExpr;
        this.type = object.type;
        this.object = object;
        this.idx = idx;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
    }
}

class IndexAssignmentDecl : Node
{
    IndexExpr idxExpr;
    this(IndexExpr idxExpr, Node value, Loc loc)
    {
        this.kind = NodeKind.IndexAssignmentDecl;
        this.idxExpr = idxExpr;
        this.value = value;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
    }
}

struct EnumField
{
    string name;
    Type type; // tipo do valor, por padrão será um inteiro
    bool defaultValue = false;
    Node value = null;
}

class EnumDeclaration : Node
{
    string name;
    EnumField[] fields;
    this(string name, ref EnumField[] fields, Loc loc, bool publico = false)
    {
        this.publico = publico;
        this.kind = NodeKind.EnumDeclaration;
        this.fields = fields;
        this.name = name;
        this.loc = loc;
        this.type = Type(Types.Enum, BaseType.Int);
        this.type.enumName = name;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        // ...
    }
}

class BreakOrContinueStmt : Node
{
    bool isBreak = false;
    this(bool isBreak, Loc loc)
    {
        this.kind = NodeKind.BreakOrContinueStmt;
        this.type = Type(Types.Void, BaseType.Void);
        this.isBreak = isBreak;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        // ...
    }
}

class WhileStatement : Node
{
    Node condition;
    Node[] body;
    this(Node condition, Node[] body, Loc loc)
    {
        this.kind = NodeKind.WhileStatement;
        this.condition = condition;
        this.body = body;
        this.type = Type(Types.Void, BaseType.Void);
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        // ...
    }
}

class ConstDeclaration : Node
{
    string id;
    this(string id, Type type, Node value, Loc loc, bool publico = false)
    {
        this.publico = publico;
        this.kind = NodeKind.ConstDeclaration;
        this.id = id;
        this.type = type;
        this.value = value;
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "ConstDeclaration: " ~ id, ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "└── Valor:", ident);
        value.get!Node.print(ident + continuation.length + 4, true);
    }
}

class ImportStatement : Node
{
    bool[string] symbols;
    this(Node file, Loc loc, bool[string] symbols)
    {
        this.kind = NodeKind.ImportStatement;
        this.type = Type(Types.Void, BaseType.Void);
        this.value = file;
        this.loc = loc;
        this.symbols = symbols;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        string prefix = isLast ? "└── " : "├── ";
        string continuation = isLast ? "    " : "│   ";

        println(prefix ~ "ImportStatement", ident);
        println(continuation ~ "├── Tipo: " ~ cast(string) type.baseType, ident);
        println(continuation ~ "├── Valor: " ~ value.get!string, ident);
    }
}

// Fim do Programa
// End of Program
class EoP : Node
{
    this(Loc loc)
    {
        this.kind = NodeKind.EoP;
        this.type = Type(Types.Undefined, BaseType.Void);
        this.loc = loc;
    }

    override void print(ulong ident = 0, bool isLast = false)
    {
        println("EoP", ident);
    }
}

// Funções auxiliares e privadas deste módulo
private void println(string message, ulong ident = 0)
{
    writeln(" ".replicate(ident), message);
}

private void print(string message, ulong ident = 0)
{
    write(" ".replicate(ident), message);
}
