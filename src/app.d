import std.stdio, std.file, std.path, std.array, std.getopt, std.datetime.stopwatch, std.algorithm, std
	.string, std.process, std.uuid;
import frontend.lexer.token, frontend.lexer.lexer;
import frontend.parser.ast, frontend.parser.parser;
import middle.semantic_analyzer, middle.harpy_optimizer;
import backend.codegen, backend.harpyvm, backend.compiler;
import core.stdc.stdlib : exit;
import core.sys.posix.dlfcn;
import erro, builtin, env;

const string VERSAO = "0.1.0";
string[] arquivosTemporarios;
void*[string] cacheGlobalBibliotecas;

version (Windows)
	string ext = ".dll";
else
	string ext = ".so";

private struct Argumentos
{
	bool versao;
	bool ajuda;
	bool token;
	bool ast;
	bool tempo;
	bool compilar;
	bool otimizar;
	bool verboso;
	bool _asm;
	bool estatico;
	bool semBiblioteca;
	string saida = "harpy.hvm";
	string[] importacoes;
}

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

void executarHvm(ref string arquivo_, bool mostrarTempo = false, void*[string] bibliotecas)
{
	scope (exit)
		limparArquivosTemporarios();

	auto tempoTotal = StopWatch(AutoStart.yes);
	auto arquivo = File(arquivo_, "rb");

	try
	{
		ubyte maior, menor, patch;

		if (!validarCabecalho(arquivo, maior, menor, patch))
		{
			writeln("O binário contém um cabeçalho inválido! O arquivo pode estar corrompido.");
			exit(1);
		}

		// loop até encontrar bytecode ou EOF
		bool encontrouBytecode = false;

		try
		{
			while (!encontrouBytecode)
			{
				ubyte tipo;
				uint tamanho;
				lerItemTLV(arquivo, tipo, tamanho);

				if (tipo == HarpyBinTipo.SECAO_BIBLIOTECA)
				{

					ubyte tipoNome;
					uint tamNome;
					lerItemTLV(arquivo, tipoNome, tamNome);

					if (tipoNome != HarpyBinTipo.BIBLIOTECA_NOME)
					{
						writeln("Esperado BIBLIOTECA_NOME, encontrado: ", tipoNome);
						throw new Exception("Formato inválido");
					}

					string nome = lerTLVTexto(arquivo, tamNome);

					// ler dados da .so ou .dll
					ubyte tipoDados;
					uint tamDados;
					lerItemTLV(arquivo, tipoDados, tamDados);
					ubyte[] dadosSo = lerTLVBytes(arquivo, tamDados);

					// salvar em arquivo temporário
					string tempPath = criarArquivoTemp(nome, dadosSo);

					// carregar dinamicamente
					void* handle = carregarBibliotecaDaMemoria(nome, dadosSo);
					if (handle)
						bibliotecas[nome] = handle;
					else
						writefln("AVISO: Falha ao carregar biblioteca %s", nome);
				}
				else if (tipo == HarpyBinTipo.SECAO_BYTECODE)
				{
					// ler bytecode
					Instruction[] programa = lerPrograma(arquivo);

					// executar
					HarpyVM motor = new HarpyVM();
					motor.libs = bibliotecas;
					motor.code = programa;

					auto tempoMotor = StopWatch(AutoStart.yes);
					motor.run();
					tempoMotor.stop();

					if (mostrarTempo)
					{
						writeln("\n---------------- Tempo ----------------:");
						mostrarStatus("motor", tempoMotor);
						mostrarStatus("total", tempoTotal);
					}

					encontrouBytecode = true;
				}
				else // tipo desconhecido, pular
					arquivo.seek(tamanho, SEEK_CUR);
			}
		}
		catch (Exception e) // se for EOF e já processou bytecode, tudo ok
			if (!encontrouBytecode)
				throw e;
	}
	catch (Exception e)
	{
		writeln("Erro ao ler o binário: ", e.msg);
		writeln("Arquivo: ", e.file);
		writeln("Linha: ", e.line);
		writeln("Rastro: ", e);
		exit(1);
	}
	finally
		arquivo.close();

	exit(0);
}

void* carregarBibliotecaDaMemoria(string nome, ubyte[] dados)
{
	if (nome in cacheGlobalBibliotecas)
		return cacheGlobalBibliotecas[nome];

	string tempPath = criarArquivoTemp(nome, dados);
	void* handle = dlopen(tempPath.toStringz, RTLD_LAZY);

	if (handle)
		cacheGlobalBibliotecas[nome] = handle;

	return handle;
}

string criarArquivoTemp(string nome, ubyte[] dados)
{
	// reusa o UUID para otimizar
	static string uuidCache;
	if (uuidCache.length == 0)
		uuidCache = randomUUID().toString();

	string caminho = buildPath(tempDir(), "harpy_" ~ uuidCache ~ "_" ~ nome ~ ext);

	std.file.write(caminho, dados);
	arquivosTemporarios ~= caminho;

	return caminho;
}

void limparArquivosTemporarios()
{
	foreach (arquivo; arquivosTemporarios)
		try
		{
			remove(arquivo);
		}
		catch (Exception)
		{ /* ignora */ }
	arquivosTemporarios.length = 0;
}

// a saida tem um arquivo padrão caso nada seja passado
// saida = "harpy.hvm"
// coloquei aqui assim como na variavel principal na função "main" por garantia
void compilarPrograma(ref Instruction[] instrucoes, string saida = "harpy.hvm", Tempo tempo,
	string[] bibliotecasExternas, bool estatico = false)
{
	ubyte[] buffer;
	auto tempoCompilacao = StopWatch(AutoStart.yes);
	adicionarCabecalho(buffer, 0, 1, 0);

	if (!estatico)
		bibliotecasExternas = [];

	adicionarPrograma(buffer, instrucoes, bibliotecasExternas);
	writeln("Compilação concluida!");
	salvarArquivoBinario(saida, buffer);
	tempoCompilacao.stop();
	tempo.tempoTotal.stop();

	if (tempo.tempo)
	{
		writeln("\n---------------- Tempo ----------------:");
		mostrarStatus("lexer", tempo.tempoLexer);
		mostrarStatus("parser", tempo.tempoParser);
		mostrarStatus("analisador semantico", tempo.tempoSA);
		mostrarStatus("gerador de bytecode", tempo.tempoCG);
		mostrarStatus("compilador", tempoCompilacao);
		mostrarStatus("total", tempo.tempoTotal);
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
		// fecha o programa com código 1 caso haja erros
		if (erro.hasErrors())
			exit(1);
		erro.clear();
	}
}

void ajuda()
{
	// mostra uma mensagem de ajuda
	writeln("Forma de uso: harpy <arquivo.rp> [opções]\n");
	writeln("Opções:");
	writeln("	-v, --versao      	Mostra a versão da maquina virtual.");
	writeln("	-a, --ajuda       	Mostra a mensagem de ajuda.");
	writeln("	-t, --tempo       	Mostra métricas de execução do programa.");
	writeln("	-c, --compilar    	Compila o programa e gera um arquivo binário.");
	writeln(
		"	-E, --estatico    	Compila o programa de forma estatica, gerando um binario mais pesado.");
	writeln("	-I, --incluir     	Inclui uma biblioteca dinamica ao motor.");
	writeln(
		"	-B, --sem-biblioteca	Ignora a biblioteca padrão do motor, não carregando ela na inicialização.");
	writeln(
		"	-o, --otimizar    	Realiza otimizações no código (use quando compilar um programa, será melhor).");
	writeln("	--verboso        	Ativa o modo verboso.");
	writeln("	--token           	Mostra os tokens (debug).");
	writeln("	--ast             	Mostra as ast's  (debug).");
	writeln(
		"	-s, --saida       	Especifica o arquivo de saida do arquivo binario (padrão = harpy.hvm).");
	writeln("\nExemplos:");
	writeln("	harpy -v");
	writeln("	harpy ola_mundo.hp");
	writeln("	harpy ola_mundo.hp --token --ast");
	writeln("	harpy ola_mundo.hp --compilar --saida ola.hvm");
	writeln("	harpy ola_mundo.hp -c -o -s ola.hvm");
}

void versao()
{
	writefln("HarpyVM - %s", VERSAO);
}

// retorna o nome da biblioteca concatenado com o diretório de bibliotecas instalado do sistema
// nome = io
// retorno = /home/<USER>/.harpy/libs/io (.so | .dll)
string criarLibSys(string nome)
{
	return DIR_LIBS ~ nome ~ ext;
}

string extrairDir(string path)
{
	string dir = dirName(path);
	return dir == "." || dir == "" ? "." : dir;
}

void mostrarStatus(string nome, StopWatch sw)
{
	writefln("%-25s %10d µs", nome, sw.peek().total!"usecs");
}

void sair(string mensagem, int codigo)
{
	writeln(mensagem);
	exit(codigo);
}

void sair_(string mensagem, int codigo)
{
	writeln(mensagem);
	ajuda();
	exit(codigo);
}

void main(string[] argumentos)
{
	// verifica se foram passados argumentos
	// o argumentos[0] por padrão contem o nome do executavel que está sendo executado
	if (argumentos.length == 1)
		sair_("Era esperado um arquivo de extensão '.rp' como argumento.", 1);

	// arquivo aparentemente passado, vamos validar
	string arquivo = argumentos[1];

	// é um arquivo ou existe?
	if (!exists(arquivo))
		sair(format("O arquivo '%s' não existe.", arquivo), 1);

	if (!isFile(arquivo))
		sair(format("'%s' não é um arquivo.", arquivo), 1);

	loadEnv();

	DiagnosticError erro = new DiagnosticError; // classe que gera os erros de todo o sistema
	Argumentos args;
	string saida = "harpy.hvm"; // arquivo padrão caso nenhuma saída seja passada

	try
	{
		// configura todos os argumentos do sistema
		getopt(argumentos,
			"v|versao", &args.versao,
			"a|ajuda", &args.ajuda,
			"token", &args.token,
			"ast", &args.ast,
			"t|tempo", &args.tempo,
			"c|compilar", &args.compilar,
			"s|saida", &args.saida,
			"o|otimizar", &args.otimizar,
			"verboso", &args.verboso,
			"asm", &args._asm,
			"E|estatico", &args.estatico,
			"I|incluir", &args.importacoes,
			"B|sem-biblioteca", &args.semBiblioteca,
		);

		if (args.versao)
		{
			versao();
			return;
		}

		if (args.ajuda)
		{
			ajuda();
			return;
		}

		// carrega bibliotecas externas, incluindo bibliotecas padrão da VM
		// bibliotecas do sistema ja estará pré carregadas
		string[] bibliotecasExternas;

		if (!args.semBiblioteca)
			bibliotecasExternas = [
				criarLibSys("entrada_saida"), criarLibSys("matematica"),
				criarLibSys("arquivo")
			];

		if (args.importacoes.length > 0)
			bibliotecasExternas ~= args.importacoes;

		// carrega todas as bibliotecas dinamicas antes de tudo executar
		// o overhead inicia aqui
		// um custo de alguns µs (microsegundos)
		void*[string] bibliotecas;
		foreach (string path; bibliotecasExternas)
		{
			if (!exists(path))
				sair(format("ERRO: A biblioteca dinamica '%s' não existe.", path), 1);

			if (path !in bibliotecas)
			{
				void* handle = dlopen(path.toStringz, RTLD_LAZY | RTLD_NODELETE);
				if (!handle)
					throw new Exception("Falha ao carregar biblioteca: " ~ path);
				string lib = replace(baseName(path), ext, "");
				bibliotecas[lib] = handle;
			}
		}

		// se a extensão for .hvm então executaremos o bytecode diretamente
		if (extension(arquivo) == ".hvm")
			executarHvm(arquivo, args.tempo, bibliotecas);

		// valida a extensão do arquivo
		if (extension(arquivo) != ".rp")
		{
			writefln("O arquivo '%s' precisa ter a extensão '.rp' ou '.hvm'.", arquivo);
			exit(1);
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

		if (args.token)
			foreach (Token token; tokens)
				token.print();

		auto tempoParser = StopWatch(AutoStart.yes);
		// segundo passe
		Program programa = new Parser(tokens, erro).parse();
		checkErrors(erro);
		tempoParser.stop();

		if (args.ast)
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

		bool[string] nomesLibsUsadas;
		foreach (lib; cg.libsUsadas.byKey)
			nomesLibsUsadas[baseName(lib).stripExtension] = true;

		// filtra removendo bibliotecas não usadas
		bibliotecasExternas = bibliotecasExternas.filter!(bibExt =>
				baseName(bibExt)
				.stripExtension in nomesLibsUsadas
		).array;

		if (args.otimizar)
		{
			if (args.verboso)
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
				if (args.verboso)
					writefln("Passe %d, %d instruções.", passe++, instrucoes
							.length);
			}
			while (instrucoes.length < tamanhoAnterior);

			if (args.verboso)
				writeln("Numero de instruções depois da otimização: : ", instrucoes.length);
		}

		// verifica se o usuário deseja compilar o programa
		if (args.compilar)
			compilarPrograma(instrucoes, saida, Tempo(args.tempo, tempoTotal, tempoLexer, tempoParser, tempoSA, tempoCG),
				bibliotecasExternas, args.estatico);

		motor.code = instrucoes;

		if (args._asm)
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

		if (args.tempo)
		{
			writeln("\n---------------- Tempo ----------------");
			mostrarStatus("lexer", tempoLexer);
			mostrarStatus("parser", tempoParser);
			mostrarStatus("analisador semantico", tempoSA);
			mostrarStatus("gerador de bytecode", tempoCG);
			mostrarStatus("motor", tempoMotor);
			mostrarStatus("total", tempoTotal);
		}
	}
	catch (Exception e)
	{
		// o tamanho da mensagem até a flag será de 20, por isso o numero magico
		if (canFind(e.msg, "Unrecognized option"))
			writefln("Opção desconhecida passada '%s', use '-a' e veja o menu de ajuda.", e
					.msg[20 .. $]);
		else
		{
			// se for um erro do sistema ele irá fechar o programa, caso contrário irá mostrar o e.msg
			checkErrors(erro);
			writeln("Erro critico: ", e.msg);
			writeln("Arquivo: ", e.file);
			writeln("Linha: ", e.line);
			writeln("Rastro: ", e);
		}
		exit(1);
	}
}
