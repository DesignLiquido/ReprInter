import std.stdio, std.file, std.path, std.array, std.getopt, std.datetime.stopwatch, std.algorithm;
import frontend.lexer.token, frontend.lexer.lexer;
import frontend.parser.ast, frontend.parser.parser;
import middle.semantic_analyzer, middle.harpy_optimizer;
import backend.codegen, backend.harpyvm, backend.compiler;
import core.stdc.stdlib : exit;
import erro;

const string VERSAO = "0.1.0";

// area de compilação do sistema {{
void executarHvm(ref string arquivo_, bool mostrarTempo = false)
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

void compilarPrograma(ref Instruction[] instrucoes, string saida = "harpy.hvm")
{
	ubyte[] buffer;
	adicionarCabecalho(buffer, 0, 1, 0);
	adicionarPrograma(buffer, instrucoes);
	writeln("Compilação concluida!");
	salvarArquivoBinario(saida, buffer);
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

void main(string[] argumentos)
{
	// suporte parcial
	// caracteres especiais podem ser imprimidos de forma incorreta
	// preciso testar muitos casos ainda, além do sistema de arquivos que necessitará
	// além disso, será preciso criar um instalador pro Windows
	// ele irá baixar alguma release pelo github, extrair o binario apenas e setar o PATH corretamente
	// não sei muito sobre instaladores do windows então se eu puder embutir o binario no instalador então assim farei
	version (Windows)
	{
		writeln("AVISO: O windows possui suporte parcial.");
		SetConsoleOutputCP(65_001);
		SetConsoleCP(65_001);
	}

	version (linux)
	{
		// ...
	}

	DiagnosticError erro = new DiagnosticError; // classe que gera os erros de todo o sistema
	bool mostrarVersao, mostrarAjuda, mostrarToken, mostrarAst, mostrarTempo, compilar, otimizar, verboso;
	string saida = "harpy.hvm";

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
			"verboso", &verboso
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

		// se a extensão for .hvm então executaremos o bytecode diretamente
		if (extension(arquivo) == ".hvm")
			executarHvm(arquivo, mostrarTempo);

		// valida a extensão do arquivo
		if (extension(arquivo) != ".rp")
		{
			writefln("O arquivo '%s' precisa ter a extensão '.rp' ou '.hvm'.", arquivo);
			exit(-1);
		}

		// ignore
		string[] bibliotecasExternas;

		// vamos salvar métricas de tempo pra analisar a velocidade do sistema
		auto tempoTotal = StopWatch(AutoStart.yes);
		// lê o arquivo e pega o conteudo
		string conteudo = readText(arquivo);
		// passa o conteudo pro lexer pegando todos os tokens criados pelo lexer

		// primeiro passe
		auto tempoLexer = StopWatch(AutoStart.yes);
		Token[] tokens = new Lexer(arquivo, conteudo, ".", erro).tokenize();
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

		// terceiro passe
		auto tempoSA = StopWatch(AutoStart.yes);
		new SemanticAnalyzer(erro).analyze(programa);
		checkErrors(erro);
		tempoSA.stop();

		// quarto passe
		HarpyVM motor = new HarpyVM();
		auto tempoCG = StopWatch(AutoStart.yes);
		Instruction[] instrucoes = new CodeGen(motor, erro, bibliotecasExternas).generate(programa);
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
			compilarPrograma(instrucoes, saida);

		motor.code = instrucoes;

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
		// se for um erro do sistema ele irá fechar o programa, caso contrário irá motrar o e.msg
		checkErrors(erro);
		writeln("Erro critico: ", e.msg);
		writeln("Arquivo: ", e.file);
		writeln("Linha: ", e.line);
		writeln("Erro critico: ", e);
		exit(-1);
	}
}
