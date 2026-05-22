module harpyvm;

import utils;

alias Program = uint*;

enum HarpyOpCode : ubyte {
    Load,
    Store,
    Add,
    Sub,
    Halt,
}

enum HarpyValueType : ubyte {
    Int,
    Float,
    Double,
    Bool,
}

union HarpyValueData {
    long l;
    double d;
    float f;
}

struct HarpyValue {
    HarpyValueType type; // 1
    HarpyValueData value; // 8
}

struct HarpyFrameCall {
    uint dpc;
    uint pc;
}

enum DATA_SIZE_INIT = 16;
enum DATA_SIZE_LIMIT = 1_000_000;

struct HarpyVirtualMachine
{
private:
    Program program;
    uint psize;
    uint pc;

    HarpyValue* data;
    uint dsize;
    uint dcap;

public:
    pragma(inline, true)
    void setup()
    {
        data = cast(HarpyValue*) calloc(1, HarpyValue.sizeof * DATA_SIZE_INIT);
        hvmAssert(data !is null, "erro ao alocar memoria pro data.");
        
        dcap = DATA_SIZE_INIT;
        for (uint i; i < dcap; i++)
            data[i] = HarpyValue.init; // inicializa todos os slots
    }

    pragma(inline, true)
    void resize(uint needed)
    {
        // se uma função precisa de N registradores e (dsize + N) > dcap
        // logo precisamos fazer um resize dos dados alocando mais memoria
        if ((dsize + needed) > dcap) return;

        uint cap = dcap;
        dcap = (dsize + needed) * 2; // poderia só dobrar a capacidade, mas vamos usar algo menos fixo baseado nas necessidades

        hvmAssert(dcap < DATA_SIZE_LIMIT, "quantidade máxima de dados alocados.");

        HarpyValue* newData = cast(HarpyValue*) calloc(1, HarpyValue.sizeof * dcap);
        hvmAssert(newData !is null, "erro ao alocar memoria pro newData.");
        
        for (uint i; i < cap; i++)
            newData[i] = data[i]; // reinsere os dados
        
        for (uint i = cap; i < dcap; i++)
            newData[i] = HarpyValue.init; // inicializa os outros slots

        free(data); // libera a memoria antiga
        data = newData; // atualiza
    }

    pragma(inline, true)
    void run()
    {
        //
    }

    pragma(inline, true)
    void destruct()
    {
        if (!data) return;
        free(data);
    }
}
