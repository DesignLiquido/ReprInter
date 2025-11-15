import std.stdio, std.file, std.path, std.array, std.getopt, std.datetime.stopwatch, std.algorithm, std
	.string, std.process;
import frontend.lexer.token, frontend.lexer.lexer;
import frontend.parser.ast, frontend.parser.parser;
import middle.semantic_analyzer, middle.harpy_optimizer;
import backend.codegen, backend.harpyvm, backend.compiler;
import core.stdc.stdlib : exit;
import core.sys.posix.dlfcn;
import erro, builtin, env;

const string VERSAO = "0.1.0";

// guarda informações de tempo para métricas, serve para passar todas as métricas para a função de compilação
// é privada pois não deve ser usada fora deste arquivo (main.d)
private struct Tempo
{
	bool tempo; // flag
	StopWatch tempoTotal;
	StopWatch tempoLexer;
	StopWatch tempoParser;
	StopWatch tempoSA;
	StopWatch tempoCG;
}

// area de compilação do sistema {{
void executarHvm(ref string arquivo_, bool mostrarTempo = false, void*[string] bibliotecas)
{
	auto tempoTotal = StopWatch(AutoStart.yes);
	auto arquivo = File(arquivo_, "rb");
	try
	{
		ubyte maior, menor, patch;

		if (!validarCabecalho(arquivo, maior, menor, patch))
		{
			writeln(
				"O binário contém contém um cabeçalho inválido! O arquivo pode estar corrompido.");
			exit(-1);
		}

		ubyte tipo;
		uint tamanho;
		lerItemTLV(arquivo, tipo, tamanho);

		if (tipo != HarpyBinTipo.SECAO_BYTECODE)
		{
			writeln(
				"O binário é inválido! O arquivo pode estar corrompido.");
			exit(-1);
		}

		Instruction[] programa = lerPrograma(arquivo);
		HarpyVM motor = new HarpyVM();
		motor.libs = bibliotecas;
		motor.code = programa;

		auto tempoMotor = StopWatch(AutoStart.yes);
		motor.run();

		tempoMotor.stop();
		tempoTotal.stop();

		if (mostrarTempo)
		{
			writefln("\nTempo do motor (execução da HarpyVM): %d µs", tempoMotor.peek()
					.total!"usecs");
			writefln("Tempo total: %d µs", tempoTotal.peek().total!"usecs");
		}
	}
	catch (Exception e)
	{
		writeln("Um erro ocorreu ao tentar ler o binário!");
		writeln(e);
		exit(-1);
	}
	finally
		arquivo.close();

	exit(0);
}

// a saida tem um arquivo padrão caso nada seja passado
// saida = "harpy.hvm"
// coloquei aqui assim como na variavel principal na função "main" por garantia
void compilarPrograma(ref Instruction[] instrucoes, string saida = "harpy.hvm", Tempo tempo)
{
	ubyte[] buffer;
	auto tempoCompilacao = StopWatch(AutoStart.yes);
	adicionarCabecalho(buffer, 0, 1, 0);
	adicionarPrograma(buffer, instrucoes);
	writeln("Compilação concluida!");
	salvarArquivoBinario(saida, buffer);
	tempoCompilacao.stop();
	tempo.tempoTotal.stop();

	if (tempo.tempo)
	{
		writefln("\nTempo do lexer (geração de tokens): %d µs", tempo.tempoLexer.peek()
				.total!"usecs");
		writefln("Tempo do parser (geração de nós): %d µs", tempo.tempoParser.peek()
				.total!"usecs");
		writefln("Tempo do analisador semantico: %d µs", tempo.tempoSA.peek()
				.total!"usecs");
		writefln("Tempo do gerador de bytecode (codegen): %d µs", tempo.tempoCG.peek()
				.total!"usecs");
		writefln("Tempo de compilação: %d µs", tempoCompilacao.peek()
				.total!"usecs");
		writefln("Tempo total: %d µs", tempo.tempoTotal.peek().total!"usecs");
	}

	exit(0);
}
// }}

// verifica se há erros ou avisos a serem mostrados
void checkErrors(DiagnosticError erro)
{
	if (erro.hasErrors() || erro.hasWarnings())
	{
		erro.printDiagnostics();
		// fecha o programa com código -1 caso haja erros
		if (erro.hasErrors())
			exit(-1);
		erro.clear();
	}
}

void ajuda()
{
	// mostra uma mensagem de ajuda
	writeln("Forma de uso: harpy <arquivo.rp> [opções]\n");
	writeln("Opções:");
	writeln("	-v, --versao      Mostra a versão da maquina virtual.");
	writeln("	-a, --ajuda       Mostra a mensagem de ajuda.");
	writeln("	-t, --tempo       Mostra métricas de execução do programa.");
	writeln("	-c, --compilar    Compila o programa e gera um arquivo binário.");
	writeln(
		"	-o, --otimizar    Realiza otimizações no código (use quando compilar um programa, será melhor).");
	writeln("	--verboso         Ativa o modo verboso.");
	writeln("	--token           Mostra os tokens (debug).");
	writeln("	--ast             Mostra as ast's  (debug).");
	writeln(
		"	-s, --saida       Especifica o arquivo de saida do arquivo binario (padrão = harpy.hvm).");
	writeln("\nExemplos:");
	writeln("	harpy -v");
	writeln("	harpy ola_mundo.hp");
	writeln("	harpy ola_mundo.hp --token --ast");
	writeln("	harpy ola_mundo.hp --compilar --saida ola.hvm");
	writeln("	harpy ola_mundo.hp -c -s -o ola.hvm");
}

void versao()
{
	// mostra uma mensagem de ajuda
	writefln("HarpyVM - %s", VERSAO);
}

// retorna o nome da biblioteca concatenado com o diretório de bibliotecas instalado do sistema
// nome = io
// retorno = /home/<USER>/.harpy/libs/io.so
string criarLibSys(string nome)
{
	return DIR_LIBS ~ nome ~ ".so";
}

string extrairDir(string path)
{
	string dir = dirName(path);
	return dir == "." || dir == "" ? "." : dir;
}

void main(string[] argumentos)
{
	loadEnv();

	DiagnosticError erro = new DiagnosticError; // classe que gera os erros de todo o sistema
	bool mostrarVersao, mostrarAjuda, mostrarToken, mostrarAst, mostrarTempo, compilar, otimizar, verboso, mostrarAsm;
	string saida = "harpy.hvm"; // arquivo padrão caso nenhuma saída seja passada

	try
	{
		// configura todos os argumentos do sistema
		getopt(argumentos,
			"v|versao", &mostrarVersao,
			"a|ajuda", &mostrarAjuda,
			"token", &mostrarToken,
			"ast", &mostrarAst,
			"t|tempo", &mostrarTempo,
			"c|compilar", &compilar,
			"s|saida", &saida,
			"o|otimizar", &otimizar,
			"verboso", &verboso,
			"asm", &mostrarAsm,
		);

		if (mostrarVersao)
		{
			versao();
			return;
		}

		if (mostrarAjuda)
		{
			ajuda();
			return;
		}

		// verifica se foram passados argumentos
		// o argumentos[0] por padrão contem o nome do executavel que está sendo executado
		if (argumentos.length == 1)
		{
			writeln("Era esperado um arquivo de extensão '.rp' como argumento.");
			ajuda();
			exit(-1);
		}

		// arquivo aparentemente passado, vamos validar
		string arquivo = argumentos[1];

		// é um arquivo ou existe?
		if (!exists(arquivo))
		{
			writefln("O arquivo '%s' não existe.", arquivo);
			return;
		}
		if (!isFile(arquivo))
		{
			writefln("'%s' não é um arquivo.", arquivo);
			exit(-1);
		}

		// carrega bibliotecas externas, incluindo bibliotecas padrão da VM
		// bibliotecas do sistema ja estará pré carregadas
		string[] bibliotecasExternas = [
			criarLibSys("entrada_saida"), criarLibSys("matematica"),
			criarLibSys("arquivo")
		];

		// carrega todas as bibliotecas dinamicas antes de tudo executar
		// o overhead inicia aqui
		// um custo de alguns µs (microsegundos)
		void*[string] bibliotecas;
		foreach (string path; bibliotecasExternas)
		{
			if (path !in bibliotecas)
			{
				void* handle = dlopen(path.toStringz, RTLD_LAZY | RTLD_NODELETE);
				if (!handle)
				{
					writefln("Erro ao carregar %s:", path);
					writeln(dlerror().fromStringz);
					throw new Exception("Falha ao carregar biblioteca: " ~ path);
				}
				bibliotecas[path] = handle;
			}
		}

		// se a extensão for .hvm então executaremos o bytecode diretamente
		if (extension(arquivo) == ".hvm")
			executarHvm(arquivo, mostrarTempo, bibliotecas);

		// valida a extensão do arquivo
		if (extension(arquivo) != ".rp")
		{
			writefln("O arquivo '%s' precisa ter a extensão '.rp' ou '.hvm'.", arquivo);
			exit(-1);
		}

		// vamos salvar métricas de tempo pra analisar a velocidade do sistema
		auto tempoTotal = StopWatch(AutoStart.yes);
		// lê o arquivo e pega o conteudo
		string conteudo = readText(arquivo);
		// passa o conteudo pro lexer pegando todos os tokens criados pelo lexer

		// primeiro passe
		auto tempoLexer = StopWatch(AutoStart.yes);
		Token[] tokens = new Lexer(arquivo, conteudo, extrairDir(arquivo), erro).tokenize();
		// esssas chamadas são feitas para verificar se há erros ou avisos no passe anterior
		// o passe é cada processo do sistema
		checkErrors(erro);

		// para a contagem de tempo
		tempoLexer.stop();

		if (mostrarToken)
			foreach (Token token; tokens)
				token.print();

		auto tempoParser = StopWatch(AutoStart.yes);
		// segundo passe
		Program programa = new Parser(tokens, erro).parse();
		checkErrors(erro);
		tempoParser.stop();

		if (mostrarAst)
			programa.print();

		// gera todo o builtin (embutido) do sistema
		// será repassado para o analisador semantico e pro codegen
		// eu registro neles e eles geram tudo automaticamente
		Builtin embutido = registrarBuiltin();

		// terceiro passe
		auto tempoSA = StopWatch(AutoStart.yes);
		SemanticAnalyzer analisadorSemantico = new SemanticAnalyzer(erro, embutido);
		analisadorSemantico.analyze(programa);
		checkErrors(erro);
		tempoSA.stop();

		// quarto passe
		HarpyVM motor = new HarpyVM();
		auto tempoCG = StopWatch(AutoStart.yes);
		CodeGen cg = new CodeGen(motor, erro, bibliotecas, embutido, analisadorSemantico
				.arquivosImportados);
		Instruction[] instrucoes = cg.generate(programa);
		tempoCG.stop();

		if (otimizar)
		{
			if (verboso)
				writeln("Numero de instruções antes da otimização: ", instrucoes.length);

			// executa passes até o numero de instruções não mudar mais
			auto cf = new HarpyOptimizer(instrucoes);
			ulong tamanhoAnterior;
			uint passe = 1;
			do
			{
				tamanhoAnterior = cast(ulong) instrucoes.length;
				instrucoes = cf.optimize();
				cf.instructions = instrucoes;
				if (verboso)
					writefln("Passe %d, %d instruções.", passe++, instrucoes
							.length);
			}
			while (instrucoes.length < tamanhoAnterior);

			if (verboso)
				writeln("Numero de instruções depois da otimização: : ", instrucoes.length);
		}

		// verifica se o usuário deseja compilar o programa
		if (compilar)
			compilarPrograma(instrucoes, saida, Tempo(mostrarTempo, tempoTotal, tempoLexer, tempoParser, tempoSA, tempoCG));

		motor.code = instrucoes;

		if (mostrarAsm)
		{
			HarpyDisassembler.run(instrucoes);
			return;
		}

		motor.libs = bibliotecas;
		motor.externalFunctions = cg.externalFunctions;

		auto tempoMotor = StopWatch(AutoStart.yes);
		// rodando tudo na vm (no motor)
		motor.run();

		tempoMotor.stop();
		tempoTotal.stop();

		if (mostrarTempo)
		{
			writefln("\nTempo do lexer (geração de tokens): %d µs", tempoLexer.peek()
					.total!"usecs");
			writefln("Tempo do parser (geração de nós): %d µs", tempoParser.peek()
					.total!"usecs");
			writefln("Tempo do analisador semantico: %d µs", tempoSA.peek()
					.total!"usecs");
			writefln("Tempo do gerador de bytecode (codegen): %d µs", tempoCG.peek()
					.total!"usecs");
			writefln("Tempo do motor (execução da HarpyVM): %d µs", tempoMotor.peek()
					.total!"usecs");
			writefln("Tempo total: %d µs", tempoTotal.peek().total!"usecs");
		}
	}
	catch (Exception e)
	{
		// if (find("Unrecognized option", e.msg))
		// {
		// 	writeln("Opção desconhecida passada: ", e.msg[20 .. $]);
		// 	ajuda();
		// 	return;
		// }
		// se for um erro do sistema ele irá fechar o programa, caso contrário irá mostrar o e.msg
		checkErrors(erro);
		writeln("Erro critico: ", e.msg);
		writeln("Arquivo: ", e.file);
		writeln("Linha: ", e.line);
		writeln("Erro critico: ", e);
		exit(-1);
	}
}
