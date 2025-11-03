import std.stdio, std.file, std.path, std.array, std.getopt, std.datetime.stopwatch;
import frontend.lexer.token, frontend.lexer.lexer;
import frontend.parser.ast, frontend.parser.parser;
import middle.semantic_analyzer;
import backend.codegen, backend.harpyvm;
import core.stdc.stdlib : exit;
import erro;

const string VERSAO = "0.1.0";

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
	writeln("	--token           Mostra os tokens (debug).");
	writeln("	--ast             Mostra as ast's  (debug).");
	writeln("	-t, --tempo       Mostra métricas de execução do programa.");
	writeln("\nExemplos:");
	writeln("	harpy -v");
	writeln("	harpy ola_mundo.hp");
	writeln("	harpy ola_mundo.hp --token --ast");
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
	bool mostrarVersao, mostrarAjuda, mostrarToken, mostrarAst, mostrarTempo;

	try
	{
		// configura todos os argumentos do sistema
		getopt(argumentos,
			"v|versao", &mostrarVersao,
			"a|ajuda", &mostrarAjuda,
			"token", &mostrarToken,
			"ast", &mostrarAst,
			"t|tempo", &mostrarTempo
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
			return;
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
			return;
		}

		// valida a extensão do arquivo
		if (extension(arquivo) != ".rp")
		{
			writefln("O arquivo '%s' precisa ter a extensão '.rp'.", arquivo);
			return;
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
		// se for um erro do sistema ele irá fechar o programa, caso contrário irá motrar o e.msg
		checkErrors(erro);
		writeln("Erro critico: ", e.msg);
		writeln("Arquivo: ", e.file);
		writeln("Linha: ", e.line);
		writeln("Erro critico: ", e);
	}
}
