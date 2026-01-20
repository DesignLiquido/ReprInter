module backend.compiler;

import std.stdio, std.file;
import std.bitmanip : nativeToLittleEndian, littleEndianToNative;
import std.exception : enforce;
import std.path : extension, setExtension, baseName;
import backend.harpyvm : OpCode, Value, EValue, Type, Instruction;
import json : ProjetoConfig, Compilacao;

// tipos de dados no formato binário da HarpyVM
enum HarpyBinTipo : ubyte
{
    CABECALHO = 1, // header "HarpyVM"
    VERSAO = 2, // versão do formato (ex: 0, 1, 0)
    SECAO_BYTECODE = 3, // bytecode da VM

    // dados primitivos
    INTEIRO = 4, // i64
    DECIMAL = 5, // f64
    TEXTO = 6, // string utf8
    LOGICO = 7, // bool
    BYTE = 8, // byte individual

    INSTRUCAO = 9, // define uma instrução
    OPCODE = 10, // define o Opcode
    VALOR_TIPO = 11, // define o tipo e consequentemente após ele virá o valor desejado

    SECAO_BIBLIOTECA = 12, // início de uma biblioteca .so
    BIBLIOTECA_NOME = 13, // nome da biblioteca
    BIBLIOTECA_DADOS = 14, // bytes da .so
    BIBLIOTECA_DEPENDENCIAS = 15, // lista de deps da lib

    // metadados do projeto
    METADADOS = 16,
    M_NOME = 17,
    M_VERSAO = 18,
    M_AUTOR = 19,
    M_DATA = 20,
    M_DESCRICAO = 21,
}

private enum BUFFER_INICIAL = 4096; // 4KB inicial

void adicionarBiblioteca(ref ubyte[] buffer, string caminho)
{
    import std.path : baseName;
    import std.file : read;

    string nome = baseName(caminho, ".so");
    ubyte[] dadosSo = cast(ubyte[]) read(caminho);

    // calcular tamanho total da seção
    // 1 + 4 + nome.length (nome TLV)
    // 1 + 4 + dadosSo.length (dados TLV)
    uint tamanhoTotal = cast(uint)((1 + 4 + nome.length) + (1 + 4 + dadosSo.length));

    // SEÇÃO BIBLIOTECA com tamanho
    buffer ~= HarpyBinTipo.SECAO_BIBLIOTECA;
    buffer ~= nativeToLittleEndian(tamanhoTotal);

    // nome (TLV interno)
    buffer ~= HarpyBinTipo.BIBLIOTECA_NOME;
    buffer ~= nativeToLittleEndian(cast(uint) nome.length);
    buffer ~= cast(ubyte[]) nome;

    // dados (TLV interno)
    buffer ~= HarpyBinTipo.BIBLIOTECA_DADOS;
    buffer ~= nativeToLittleEndian(cast(uint) dadosSo.length);
    buffer ~= dadosSo;
}

// adiciona cabeçalho mágico "HarpyVM" + versão
void adicionarCabecalho(ref ubyte[] buffer, ubyte versaoMaior = 0,
    ubyte versaoMenor = 1, ubyte versaoPatch = 0)
{
    // pre-alocar espaço estimado se buffer estiver vazio
    if (buffer.length == 0)
        buffer.reserve(BUFFER_INICIAL);

    // magic bytes: "HarpyVM"
    adicionarTLVTexto(buffer, "HarpyVM");

    // versão (3 bytes)
    buffer ~= HarpyBinTipo.VERSAO;
    buffer ~= nativeToLittleEndian(3u); // 3 bytes
    buffer ~= [versaoMaior, versaoMenor, versaoPatch];
}

void adicionarTLVTexto(ref ubyte[] buffer, string texto)
{
    uint tamanho = cast(uint) texto.length;
    // pre-alocar espaço necessário (1 tipo + 4 tamanho + N dados)
    uint tamanhoTotal = 1 + 4 + tamanho;
    buffer.reserve(buffer.length + tamanhoTotal);
    buffer ~= HarpyBinTipo.TEXTO;
    buffer ~= nativeToLittleEndian(tamanho);
    buffer ~= cast(ubyte[]) texto;
}

void adicionarTLVInteiro(ref ubyte[] buffer, long valor)
{
    buffer.reserve(buffer.length + 13); // 1 + 4 + 8
    buffer ~= HarpyBinTipo.INTEIRO;
    buffer ~= nativeToLittleEndian(8u); // 8 bytes
    buffer ~= nativeToLittleEndian(valor);
}

void adicionarTLVDecimal(ref ubyte[] buffer, double valor)
{
    buffer.reserve(buffer.length + 13); // 1 + 4 + 8
    buffer ~= HarpyBinTipo.DECIMAL;
    buffer ~= nativeToLittleEndian(8u); // 8 bytes

    // converter double para bytes de forma portável
    union DoubleBytes
    {
        double d;
        ubyte[8] bytes;
    }

    DoubleBytes db;
    db.d = valor;
    buffer ~= db.bytes[];
}

void adicionarTLVLogico(ref ubyte[] buffer, bool valor)
{
    buffer.reserve(buffer.length + 6); // 1 + 4 + 1
    buffer ~= HarpyBinTipo.LOGICO;
    buffer ~= nativeToLittleEndian(1u); // 1 byte
    buffer ~= cast(ubyte)(valor ? 1 : 0);
}

void adicionarSecao(ref ubyte[] buffer, HarpyBinTipo tipoSecao)
{
    buffer.reserve(buffer.length + 6);
    buffer ~= tipoSecao; // tipo da seção diretamente
    buffer ~= nativeToLittleEndian(1u);
    buffer ~= tipoSecao;
}

void adicionarInstrucao(ref ubyte[] buffer, OpCode op, Value val)
{
    buffer.reserve(buffer.length + 64); // aloca espaço estimado

    buffer ~= HarpyBinTipo.INSTRUCAO;

    // calcular tamanho total da instrução
    // 1 byte OpCode + 1 byte Type + tamanho do valor
    uint tamanhoInstrucao = 2; // opcode + type

    // adicionar tamanho do valor baseado no tipo
    final switch (val.type)
    {
    case Type.Int:
        tamanhoInstrucao += 8;
        break;
    case Type.Float:
        tamanhoInstrucao += 8;
        break;
    case Type.Bool:
        tamanhoInstrucao += 1;
        break;
    case Type.String:
        tamanhoInstrucao += 4 + val.value.str.length; // tamanho + string
        break;
    case Type.Array:
    case Type.Struct:
    case Type.Enum:
        // Arrays são mais complexos, vamos simplificar por enquanto
        tamanhoInstrucao += 4; // apenas o count por enquanto
        break;
    }

    buffer ~= nativeToLittleEndian(tamanhoInstrucao);
    // adicionar OpCode
    buffer ~= cast(ubyte) op;
    // adicionar Type
    buffer ~= cast(ubyte) val.type;

    // Adicionar valor baseado no tipo
    final switch (val.type)
    {
    case Type.Int:
        buffer ~= nativeToLittleEndian(val.value.i64);
        break;

    case Type.Float:
        union DoubleBytes
        {
            double d;
            ubyte[8] bytes;
        }

        DoubleBytes db;
        db.d = val.value.f64;
        buffer ~= db.bytes[];
        break;

    case Type.Bool:
        buffer ~= cast(ubyte)(val.value.i1 ? 1 : 0);
        break;

    case Type.String:
        uint strLen = cast(uint) val.value.str.length;
        buffer ~= nativeToLittleEndian(strLen);
        buffer ~= cast(ubyte[]) val.value.str;
        break;

    case Type.Array:
    case Type.Struct:
    case Type.Enum:
        uint arrLen = cast(uint) val.value.array.length;
        buffer ~= nativeToLittleEndian(arrLen);
        // TODO: serializar cada elemento do array
        break;
    }
}

void adicionarMetadados(ref ubyte[] buffer, ProjetoConfig projeto = ProjetoConfig.init)
{
    import std.datetime;

    string formatarDataBR()
    {
        // formata a data com fuso horario BR
        auto tz = new immutable SimpleTimeZone(hours(-3));
        auto data = Clock.currTime(tz);
        import std.format;

        return format("%02d/%02d/%d às %02d:%02d:%02d",
            data.day,
            data.month,
            data.year,
            data.hour,
            data.minute,
            data.second);
    }

    string dataBR = formatarDataBR();

    // calcular tamanho total da seção de metadados
    // cada campo tem: 1 byte (tipo do campo) + conteúdo TLV (1 + 4 + tamanho_string)
    uint tamanhoTotal = 0;
    tamanhoTotal += 1 + (1 + 4 + projeto.nome.length); // M_NOME
    tamanhoTotal += 1 + (1 + 4 + projeto.versao.length); // M_VERSAO
    tamanhoTotal += 1 + (1 + 4 + projeto.autor.length); // M_AUTOR
    tamanhoTotal += 1 + (1 + 4 + dataBR.length); // M_DATA
    tamanhoTotal += 1 + (1 + 4 + projeto.descricao.length); // M_DESCRICAO

    buffer ~= HarpyBinTipo.METADADOS;
    buffer ~= nativeToLittleEndian(tamanhoTotal);

    buffer ~= HarpyBinTipo.M_NOME;
    adicionarTLVTexto(buffer, projeto.nome);
    buffer ~= HarpyBinTipo.M_VERSAO;
    adicionarTLVTexto(buffer, projeto.versao);
    buffer ~= HarpyBinTipo.M_AUTOR;
    adicionarTLVTexto(buffer, projeto.autor);
    buffer ~= HarpyBinTipo.M_DATA;
    adicionarTLVTexto(buffer, dataBR);
    buffer ~= HarpyBinTipo.M_DESCRICAO;
    adicionarTLVTexto(buffer, projeto.descricao);
}

void adicionarPrograma(ref ubyte[] buffer, Instruction[] instrucoes,
    string[] bibliotecasUsadas = [])
{
    foreach (caminho; bibliotecasUsadas)
        if (exists(caminho))
            adicionarBiblioteca(buffer, caminho);

    // seção de bytecode
    buffer ~= HarpyBinTipo.SECAO_BYTECODE;
    // calcular tamanho total da seção
    uint tamanhoTotal = 4; // número de instruções (uint)
    foreach (ref inst; instrucoes)
        tamanhoTotal += calcularTamanhoInstrucao(inst);

    buffer ~= nativeToLittleEndian(tamanhoTotal);
    buffer ~= nativeToLittleEndian(cast(uint) instrucoes.length);

    // serializar cada instrução
    foreach (ref inst; instrucoes)
        adicionarInstrucao(buffer, inst.op, inst.val);
}

private uint calcularTamanhoInstrucao(ref Instruction inst)
{
    // 1 (tipo INSTRUCAO) + 4 (tamanho) + conteúdo
    uint tam = 5 + 2; // header + opcode + type

    final switch (inst.val.type)
    {
    case Type.Int:
        tam += 8;
        break;
    case Type.Float:
        tam += 8;
        break;
    case Type.Bool:
        tam += 1;
        break;
    case Type.String:
        tam += 4 + inst.val.value.str.length;
        break;
    case Type.Array:
    case Type.Struct:
    case Type.Enum:
        tam += 4;
        break; // simplificado
    }

    return tam;
}

Instruction lerInstrucao(ref File arquivo, uint tamanho)
{
    enforce(tamanho >= 2, "Instrução muito pequena");

    // OpCode
    ubyte[1] opBuf;
    arquivo.rawRead(opBuf);
    OpCode op = cast(OpCode) opBuf[0];

    // Type
    ubyte[1] typeBuf;
    arquivo.rawRead(typeBuf);
    Type tipo = cast(Type) typeBuf[0];

    // valor baseado no tipo
    EValue ev;

    final switch (tipo)
    {
    case Type.Int:
        ubyte[8] buf;
        arquivo.rawRead(buf);
        ev.i64 = littleEndianToNative!long(buf);
        break;

    case Type.Float:
        ubyte[8] buf;
        arquivo.rawRead(buf);
        union DoubleBytes
        {
            double d;
            ubyte[8] bytes;
        }

        DoubleBytes db;
        db.bytes[] = buf[];
        ev.f64 = db.d;
        break;

    case Type.Bool:
        ubyte[1] buf;
        arquivo.rawRead(buf);
        ev.i1 = buf[0] != 0;
        break;

    case Type.String:
        ubyte[4] lenBuf;
        arquivo.rawRead(lenBuf);
        uint strLen = littleEndianToNative!uint(lenBuf);

        auto strBuf = new ubyte[strLen];
        arquivo.rawRead(strBuf);
        ev.str = cast(string) strBuf;
        break;

    case Type.Array:
    case Type.Struct:
    case Type.Enum:
        ubyte[4] lenBuf;
        arquivo.rawRead(lenBuf);
        uint arrLen = littleEndianToNative!uint(lenBuf);
        ev.array = new Value[arrLen];
        // TODO: ler cada elemento
        break;
    }

    return Instruction(op, Value(tipo, ev));
}

Instruction[] lerPrograma(ref File arquivo)
{
    // número de instruções
    ubyte[4] countBuf;
    arquivo.rawRead(countBuf);
    uint numInstrucoes = littleEndianToNative!uint(countBuf);
    auto instrucoes = new Instruction[numInstrucoes];

    foreach (i; 0 .. numInstrucoes)
    {
        ubyte tipo;
        uint tam;
        lerItemTLV(arquivo, tipo, tam);

        enforce(tipo == HarpyBinTipo.INSTRUCAO, "Esperado tipo INSTRUCAO");
        instrucoes[i] = lerInstrucao(arquivo, tam);
    }

    return instrucoes;
}

void lerItemTLV(ref File arquivo, out ubyte tipo, out uint tamanho)
{
    ubyte[1] bufferTipo;
    ubyte[4] bufferTamanho;

    // tipo
    auto resultadoTipo = arquivo.rawRead(bufferTipo);
    enforce(resultadoTipo.length == 1, "Fim inesperado ao ler tipo TLV");
    tipo = bufferTipo[0];

    // tamanho (little-endian)
    auto resultadoTamanho = arquivo.rawRead(bufferTamanho);
    enforce(resultadoTamanho.length == 4, "Falha ao ler tamanho do campo TLV");
    tamanho = littleEndianToNative!uint(bufferTamanho);
}

string lerTLVTexto(ref File arquivo, uint tamanho)
{
    enforce(tamanho <= 100_000_000, "Tamanho de texto suspeito (>100MB)"); // proteção contra corrupção
    auto buffer = new ubyte[tamanho];
    auto resultado = arquivo.rawRead(buffer);
    enforce(resultado.length == tamanho, "Falha ao ler dados de texto");
    return cast(string) buffer;
}

long lerTLVInteiro(ref File arquivo, uint tamanho)
{
    enforce(tamanho == 8, "Tamanho inválido para inteiro - esperado 8 bytes");
    ubyte[8] buffer;
    auto resultado = arquivo.rawRead(buffer);
    enforce(resultado.length == 8, "Falha ao ler dados de inteiro");
    return littleEndianToNative!long(buffer);
}

double lerTLVDecimal(ref File arquivo, uint tamanho)
{
    enforce(tamanho == 8, "Tamanho inválido para decimal - esperado 8 bytes");
    ubyte[8] buffer;
    auto resultado = arquivo.rawRead(buffer);
    enforce(resultado.length == 8, "Falha ao ler dados de decimal");

    union DoubleBytes
    {
        double d;
        ubyte[8] bytes;
    }

    DoubleBytes db;
    db.bytes[] = buffer[];
    return db.d;
}

bool lerTLVLogico(ref File arquivo, uint tamanho)
{
    enforce(tamanho == 1, "Tamanho inválido para lógico - esperado 1 byte");
    ubyte[1] buffer;
    auto resultado = arquivo.rawRead(buffer);
    enforce(resultado.length == 1, "Falha ao ler dados lógicos");
    return buffer[0] != 0;
}

ubyte[] lerTLVBytes(ref File arquivo, uint tamanho)
{
    enforce(tamanho <= 100_000_000, "Tamanho de bytes suspeito (>100MB)");
    auto buffer = new ubyte[tamanho];
    auto resultado = arquivo.rawRead(buffer);
    enforce(resultado.length == tamanho, "Falha ao ler sequência de bytes");
    return buffer;
}

bool validarCabecalho(ref File arquivo, out ubyte versaoMaior,
    out ubyte versaoMenor, out ubyte versaoPatch)
{
    try
    {
        ubyte tipo;
        uint tamanho;

        // magic bytes
        lerItemTLV(arquivo, tipo, tamanho);
        if (tipo != HarpyBinTipo.TEXTO)
            return false;

        string magico = lerTLVTexto(arquivo, tamanho);
        if (magico != "HarpyVM")
            return false;

        // versão
        lerItemTLV(arquivo, tipo, tamanho);
        if (tipo != HarpyBinTipo.VERSAO || tamanho != 3)
            return false;

        ubyte[3] versao;
        auto resultado = arquivo.rawRead(versao);
        if (resultado.length != 3)
            return false;

        versaoMaior = versao[0];
        versaoMenor = versao[1];
        versaoPatch = versao[2];

        return true;
    }
    catch (Exception e)
        return false;
}

void salvarArquivoBinario(string nomeArquivo, const ubyte[] buffer)
{
    // hvm = HarpyVM
    if (extension(nomeArquivo) != ".hvm")
        nomeArquivo = setExtension(nomeArquivo, "hvm");

    std.file.write(nomeArquivo, buffer);
    writefln("✓ Arquivo binário salvo: %s (%d bytes)", nomeArquivo, buffer.length);
}

ubyte[] carregarArquivoBinario(string nomeArquivo)
{
    enforce(exists(nomeArquivo), "Arquivo não encontrado: " ~ nomeArquivo);
    enforce(isFile(nomeArquivo), "Caminho não é um arquivo: " ~ nomeArquivo);
    auto dados = cast(ubyte[]) std.file.read(nomeArquivo);
    enforce(dados.length > 0, "Arquivo vazio: " ~ nomeArquivo);
    return dados;
}
