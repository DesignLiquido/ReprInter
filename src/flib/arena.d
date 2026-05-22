module flib.arena;

import utils;

private struct Chunk
{
    char* data = null; // dados (8)
    uint size, capacity = 0; // tamanho atual e capacidade (8)
    Chunk* next = null; // proximo chunk (8)
}

struct Arena
{
private:
    Chunk* chunk;
    bool canReset = false;

    pragma(inline, true)
    void checkChunk(Chunk* _)
    {
        if (_) return;
        printf("erro ao alocar chunk principal.");
        exit(1);
    }

    pragma(inline, true)
    Chunk* foundChunk(uint need)
    {
        Chunk* c = this.chunk;
        while (c)
        {
            // se tiver espaço livre entao retorna o chunk
            if ((c.size + need) <= c.capacity && c.data)
                return c;
            c = c.next; // atualiza
        }
        return null; // não achou
    }

    Chunk* newChunk(Chunk* c, uint ali)
    {
        Chunk* _ = cast(Chunk*) calloc(1, Chunk.sizeof); // chunk novo
        uint capacity = c.capacity * 2 + ali;
        checkChunk(_);
        _.next = c; // o proximo chunk é o atual utilizado
        _.capacity = capacity; // aloca um espaço maior (fator 2c + s)
        _.data = cast(char*) calloc(1, capacity); // aloca a nova capacidade de dados
        return _;
    }

public:
    this(uint size, bool canReset = false)
    {
        uint ali = (size + 7) & ~7;
        Chunk* _ = cast(Chunk*) calloc(1, Chunk.sizeof);
        checkChunk(_);
        _.capacity = ali; // usa o tamanho alinhado
        _.data = cast(char*) calloc(1, ali);
        this.chunk = _;
        this.canReset = canReset;
    }

    void* alloc(uint size)
    {
        Chunk* c = this.chunk;
        uint ali = (size + 7) & ~7; // alinhamento do tamanho atual
        if ((c.size + ali) > c.capacity || !c.data)
        {
            bool found = false;
            if (canReset)
            {
                // se pode resetar então tenta achar um chunk livre
                Chunk* nc = foundChunk(ali);
                if (nc)
                {
                    found = true;
                    c = nc; // atualiza pro chunk livre
                }
            }
            // se não achar criará um chunk novo
            if (!found)
            {
                // realocar consiste em criar um chunk novo com uma capacidade maior
                Chunk* c2 = newChunk(c, ali);
                this.chunk = c2;
                c = c2;
            }
        }
        void* data = cast(void*) (c.data + c.size); // dados
        c.size += ali; // atualiza
        return data;
    }

    void destruct()
    {
        Chunk* c = this.chunk;
        while (c)
        {
            free(cast(void*) c.data); // desaloca os recursos atuais
            Chunk* next = c.next; // salva o next
            free(cast(void*) c); // libera o chunk atual alocado
            c = next; // atualiza
        }
    }

    void reset()
    {
        if (!canReset)
            return;
        
        Chunk* c = this.chunk;
        while (c)
        {
            c.size = 0; // zera o tamanho de todos os chunks
            c = c.next; // atualiza
        }
    }
}
