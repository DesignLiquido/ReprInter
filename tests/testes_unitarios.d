module tests.testes_unitarios;

// comando usado para compilar:
// rdmd tests/testes_unitarios.d

import std.stdio, std.process, std.file, std.path, std.array, std.string, std.conv, std.algorithm;
import std.datetime.stopwatch : StopWatch, AutoStart;

enum ModoExecucao
{
    Interpretado, // Executa direto
    Compilado // Compila e executa o binário
}

struct CasoTeste
{
    string nome;
    string arquivoFonte;
    string[] saidaEsperada;
    int timeoutSegundos = 5;
}

struct ResultadoTeste
{
    bool sucesso;
    string mensagemErro;
    long tempoMs;
}

// Gerenciador de testes do Harpy
// é o mesmo sistema que é utilizado no Compilador Geral Delégua (cgd)
// apenas dei uma melhorada e modificada
class TestadorHarpy
{
    private CasoTeste[] casos;
    private int aprovados;
    private int falhados;
    private string caminhoExecutavel = "./harpy";
    private string diretorioBinarios = "bin_testes";

    this(string executavel = "./harpy")
    {
        caminhoExecutavel = executavel;

        if (!exists(diretorioBinarios))
            mkdir(diretorioBinarios);
    }

    void adicionar(CasoTeste caso)
    {
        casos ~= caso;
    }

    void adicionar(CasoTeste[] novoscasos)
    {
        casos ~= novoscasos;
    }

    void executar(ModoExecucao modo)
    {
        aprovados = 0;
        falhados = 0;

        writeln("🧪 Executando testes da HarpyVM - Modo: ", modo);
        writeln("═══════════════════════════════════════════════");
        writeln();

        auto cronometro = StopWatch(AutoStart.yes);

        foreach (caso; casos)
        {
            auto resultado = modo == ModoExecucao.Interpretado
                ? executarInterpretado(caso) : executarCompilado(caso);

            exibirResultado(caso, resultado);

            if (resultado.sucesso)
                aprovados++;
            else
                falhados++;
        }

        cronometro.stop();
        exibirResumo(cronometro.peek.total!"msecs");
    }

    private ResultadoTeste executarInterpretado(CasoTeste caso)
    {
        auto cronometro = StopWatch(AutoStart.yes);
        try
        {
            auto resultado = executeShell(
                format("%s %s", caminhoExecutavel, caso.arquivoFonte),
                null,
                Config.none,
                long.max,
                "."
            );

            cronometro.stop();

            if (resultado.status != 0)
                return ResultadoTeste(
                    false,
                    format("Falha na interpretação: %s", resultado.output),
                    cronometro.peek.total!"msecs"
                );

            if (!verificarSaida(resultado.output, caso.saidaEsperada))
                return ResultadoTeste(
                    false,
                    format("Saída incorreta.\nEsperado:\n%s\n\nRecebido:\n%s",
                        caso.saidaEsperada.join("\n"),
                        resultado.output.strip()
                ),
                cronometro.peek.total!"msecs"
                );

            return ResultadoTeste(true, "", cronometro.peek.total!"msecs");
        }
        catch (Exception e)
        {
            cronometro.stop();
            return ResultadoTeste(
                false,
                format("Exceção: %s", e.msg),
                cronometro.peek.total!"msecs"
            );
        }
    }

    private ResultadoTeste executarCompilado(CasoTeste caso)
    {
        auto cronometro = StopWatch(AutoStart.yes);
        string binario = buildPath(
            diretorioBinarios,
            caso.nome.replace(" ", "_").toLower()
        );

        try
        {
            auto compilacao = executeShell(
                format("%s %s -c -s %s",
                    caminhoExecutavel,
                    caso.arquivoFonte,
                    binario
            ),
            null,
            Config.none,
            long.max,
            "."
            );

            if (compilacao.status != 0)
            {
                cronometro.stop();
                return ResultadoTeste(
                    false,
                    format("Falha na compilação: %s", compilacao.output),
                    cronometro.peek.total!"msecs"
                );
            }

            auto execucao = executeShell(format("%s %s.hvm", caminhoExecutavel, binario));
            cronometro.stop();

            if (execucao.status != 0)
            {
                limparBinario(binario);
                return ResultadoTeste(
                    false,
                    format("Falha na execução: %s", execucao.output),
                    cronometro.peek.total!"msecs"
                );
            }

            if (!verificarSaida(execucao.output, caso.saidaEsperada))
            {
                limparBinario(binario);
                return ResultadoTeste(
                    false,
                    format("Saída incorreta.\nEsperado:\n%s\n\nRecebido:\n%s",
                        caso.saidaEsperada.join("\n"),
                        execucao.output.strip()
                ),
                cronometro.peek.total!"msecs"
                );
            }

            limparBinario(binario);
            return ResultadoTeste(true, "", cronometro.peek.total!"msecs");
        }
        catch (Exception e)
        {
            cronometro.stop();
            limparBinario(binario);
            return ResultadoTeste(
                false,
                format("Exceção: %s", e.msg),
                cronometro.peek.total!"msecs"
            );
        }
    }

    private bool verificarSaida(string saidaReal, string[] saidaEsperada)
    {
        if (saidaEsperada.length == 0)
            return true;

        auto linhasReais = saidaReal.strip().split('\n');

        if (linhasReais.length != saidaEsperada.length)
            return false;

        foreach (i, linha; linhasReais)
            if (linha.strip() != saidaEsperada[i].strip())
                return false;

        return true;
    }

    private void limparBinario(string caminho)
    {
        if (exists(caminho))
            try
                remove(caminho);
            catch (Exception)
            { /* Ignora erros de limpeza */ }
    }

    private void exibirResultado(CasoTeste caso, ResultadoTeste resultado)
    {
        write("  ", caso.nome, " ");

        if (resultado.sucesso)
            writefln("✅ (%d ms)", resultado.tempoMs);
        else
        {
            writeln("❌");
            writeln("    └─ ", resultado.mensagemErro.replace("\n", "\n       "));
            writeln();
        }
    }

    private void exibirResumo(long tempoTotal)
    {
        writeln();
        writeln("📊 Resumo");
        writeln("═══════════════════════════════════════════════");
        writefln("  ✅ Aprovados: %d", aprovados);
        writefln("  ❌ Falhados:  %d", falhados);
        writefln("  📋 Total:     %d", aprovados + falhados);
        writefln("  ⏱️  Tempo:     %d ms", tempoTotal);
        writeln();

        if (falhados == 0)
            writeln("🎉 Todos os testes passaram! 🚀");
        else
            writefln("⚠️  %d teste(s) falharam.", falhados);
    }

    double taxaSucesso() const
    {
        int total = aprovados + falhados;
        return total > 0 ? cast(double) aprovados / total : 0.0;
    }
}

void main(string[] args)
{
    auto testador = new TestadorHarpy("./harpy");
    testador.adicionar([
        CasoTeste(
            "Olá Mundo",
            "exemplos/ola_mundo.rp",
            ["Olá Mundo!"]
        ),
        CasoTeste("Operações Bitwise",
            "exemplos/bit_a_bit.rp",
            [
                "r1 = 15",
                "r2 = 24",
                "r3 = 2",
                "r4 = 0",
                "r5 = 3",
                "r6 = 1",
                "x = (x << 2) + (x & 3) -> 42",
                "x ^= (a | b) -> 45",
                "x &= ((a << 1) + b) -> 13",
                "x >>= 1 -> 6"
            ]),
        CasoTeste(
            "Fibonacci",
            "exemplos/fibo.rp",
            ["Fibonacci(10) = 55"],
            15
        ),
        CasoTeste(
            "Argumento padrão",
            "exemplos/argumento_padrao.rp",
            ["69"]
        ),
        CasoTeste(
            "Leitura de arquivo",
            "exemplos/arquivo.rp",
            [
                "Arquivo de teste para verificar se a função \"lerArquivo\" está funcionando corretamente"
            ]
        ),
        CasoTeste(
            "Enquanto",
            "exemplos/enquanto.rp",
            [
                "0",
                "1",
                "2",
                "3",
                "4",
                "5",
                "6",
                "7",
                "8",
                "9",
            ]
        ),
        CasoTeste(
            "Enumeração",
            "exemplos/enum.rp",
            ["Sucesso ao validar"]
        ),
        CasoTeste(
            "Estrutura",
            "exemplos/estrutura.rp",
            [
                "Fernando",
                "João",
                "Fernando",
                "Nando",
                "Alterado",
                "Alterado",
                "Desconhecido"
            ]
        ),
        CasoTeste(
            "FFI",
            "exemplos/ffi.rp",
            ["69"]
        ),
        CasoTeste(
            "Logs",
            "exemplos/logs.rp",
            [
                "[INFO] Sistema iniciado",
                "[ERROR] Erro crítico!",
                "[DEBUG] Debug info"
            ]
        ),
        CasoTeste(
            "Matematica",
            "exemplos/matematica.rp",
            ["0", "4"]
        ),
        CasoTeste(
            "Ola",
            "exemplos/ola.rp",
            ["Ola Fernando"]
        ),
        CasoTeste(
            "Para",
            "exemplos/para.rp",
            ["0 1 2 3 4 5 6 7 8 9"]
        ),
        CasoTeste(
            "Tipo qualquer",
            "exemplos/qualquer.rp",
            [
                "69",
                "69.00000002",
                "69.00000000"
            ]
        ),
        CasoTeste(
            "Saudar",
            "exemplos/saudar.rp",
            [
                "Olá, Visitante! Idade: 18",
                "Olá, Ana! Idade: 18",
                "Olá, João! Idade: 25"
            ]
        ),
        CasoTeste(
            "Vetor",
            "exemplos/vetor.rp",
            [
                "Fernando",
                "Marcelo Andrade",
                "Fernando",
                "Olá Fernando",
                "Olá Jonas",
            ]
        ),
    ]);

    bool interpretado = args.length > 1 && args[1] == "interpretar";
    bool compilado = args.length > 1 && args[1] == "compilar";
    bool ambos = args.length == 1 || args[1] == "todos";

    if (interpretado || ambos)
    {
        testador.executar(ModoExecucao.Interpretado);
        writeln();
    }

    if (compilado || ambos)
    {
        testador.executar(ModoExecucao.Compilado);
        writeln();
    }

    if (ambos)
        writefln("Taxa de sucesso geral: %.1f%%", testador.taxaSucesso() * 100);
}
