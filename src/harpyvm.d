// Harpy Virutal Machine - Baseada em registradores, leve e otimizada
// muito inspirada pela VM de Lua e pela JVM, o objetivo é se tornar backend de absolutamente qualquer linguagem de programação interpretada
// com um sistema de tipos extremamente rico suportando estruturas de dados complexas nativamente como arrays, hashtables e objects
// Fernando © 2025
module harpyvm;

@nogc:
extern(C):

import core.stdc.stdio, core.stdc.stdlib;

enum HVMType : ubyte {
    Int, //       i32 4 bytes
    Uint, //      u32 4 bytes
    Long, //      i64 8 bytes
    Ulong, //     u64 8 bytes
    Byte, //      i8  1 byte
    Ubyte, //     u8  1 byte
    Char, //      i8  1 byte
    Short, //     i16 2 bytes
    Ushort, //    u16 2 bytes
    Bool, //      i1  1 byte (1 bit)
    String, //    struct HVMString
    HashTable, // struct HVMHashTable
    Object, //    struct HVMObject
}

struct HVMString {}
struct HVMHashTable {}
struct HVMObject {}

union HVMLiteral {
    int i32;
    uint u32;
    long i64;
    ulong u64;
    byte i8; // byte e char
    ubyte u8;
    short i16;
    ushort u16;
    bool i1;
    HVMString str;
    HVMHashTable ht;
    HVMObject obj;
}

// toda instrução 4 bytes (32 bits), nada a mais

enum HVMOpCode : ubyte {
    Loadk, // carrega uma constante do pool
    Loadkx, // carregar uma constante com IDX grande do pool
    Pop, // remove um valor da stack
    Call, // chamada em função normal com `ret`
    Callb, // chamada em função builtin
    Callf, // chamada em função ffi
    Ret, // retorna pro `pc` anterior
    
    // genericos pra qualquer tipo prevalecendo o tipo maior, suportam fastPath para operações com o mesmo tipo
    // prefixo B indica BitWise
    Add, // +
    Sub, // -
    Mul, // *
    Div, // /
    BShl, // >>
    BShll, // >>>
    BShr, // <<
    BXor, // ^
    BAnd, // &
    BNot, // ~
    Lt, // <
    Gt, // >
    Lte, // <=
    Gte, // >=
    Eq, // ==
    Neq, // !=
    
    Hlt,
}

struct HVM {
    
}
