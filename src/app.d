import std.stdio, std.file, std.path, std.array, std.getopt, std.datetime.stopwatch, std.algorithm, std
	.string, std.process, std.uuid, std.bitmanip;
import frontend.lexer.token, frontend.lexer.lexer;
import frontend.parser.ast, frontend.parser.parser;
import middle.semantic_analyzer, middle.harpy_optimizer;
import backend.codegen, backend.harpyvm, backend.compiler;
import core.stdc.stdlib : exit;
import core.sys.posix.dlfcn;
import erro, builtin, env, json;

const string VERSAO = "0.1.0";
string[] arquivosTemporarios;
void*[string] cacheGlobalBibliotecas;
ProjetoConfig projeto;

version (Windows)
	string ext = ".dll";
else version (linux)
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
	bool info;
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
					criarArquivoTemp(nome, dadosSo);

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

version (linux)
{
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
}
else version (Windows)
{
	void* carregarBibliotecaDaMemoria(string nome, ubyte[] dados)
	{
		void* handle = null;
		return handle;
	}
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

	adicionarMetadados(buffer, projeto);
	adicionarPrograma(buffer, instrucoes, bibliotecasExternas);
	salvarArquivoBinario(saida, buffer);

	writeln("Compilação concluida!");
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

void sair(string mensagem, int codigo = 1)
{
	writeln(mensagem);
	exit(codigo);
}

void sair_(string mensagem, int codigo = 1)
{
	writeln(mensagem);
	ajuda();
	exit(codigo);
}

void info(string arquivo)
{
	auto arq = File(arquivo, "rb");
	scope (exit)
		arq.close();

	try
	{
		ubyte maior, menor, patch;

		if (!validarCabecalho(arq, maior, menor, patch))
			sair("Erro: Cabeçalho inválido!");

		writefln("=== Informações do Binário ===\n");
		writefln("Arquivo: %s", baseName(arquivo));
		writefln("Tamanho: %.2f KB (%d bytes)", getSize(arquivo) / 1024.0, getSize(arquivo));
		writefln("Versão do formato: %d.%d.%d", maior, menor, patch);

		uint numInstrucoes = 0;
		uint numBibliotecas = 0;
		ulong tamanhoBibliotecas = 0;
		ulong tamanhoBytecode = 0;
		string[string] metadados;
		string[] bibliotecas;
		bool temMetadados = false;

		while (!arq.eof())
		{
			ubyte tipo;
			uint tamanho;

			try
				lerItemTLV(arq, tipo, tamanho);
			catch (Exception)
				break;

			if (tipo == HarpyBinTipo.METADADOS)
			{
				temMetadados = true;
				long posInicial = arq.tell();
				long posFinal = posInicial + tamanho;

				while (arq.tell() < posFinal)
				{
					ubyte[1] tipoMetaBuf;
					arq.rawRead(tipoMetaBuf);
					ubyte tipoMeta = tipoMetaBuf[0];

					ubyte tipoTexto;
					uint tamTexto;
					lerItemTLV(arq, tipoTexto, tamTexto);
					string valor = lerTLVTexto(arq, tamTexto);

					switch (tipoMeta)
					{
					case HarpyBinTipo.M_NOME:
						metadados["nome"] = valor;
						break;
					case HarpyBinTipo.M_VERSAO:
						metadados["versao"] = valor;
						break;
					case HarpyBinTipo.M_AUTOR:
						metadados["autor"] = valor;
						break;
					case HarpyBinTipo.M_DATA:
						metadados["data"] = valor;
						break;
					case HarpyBinTipo.M_DESCRICAO:
						metadados["descricao"] = valor;
						break;
					default:
						break;
					}
				}
			}
			else if (tipo == HarpyBinTipo.SECAO_BIBLIOTECA)
			{
				numBibliotecas++;
				tamanhoBibliotecas += tamanho;

				ubyte tipoNome;
				uint tamNome;
				lerItemTLV(arq, tipoNome, tamNome);
				string nomeBib = lerTLVTexto(arq, tamNome);

				ubyte tipoDados;
				uint tamDados;
				lerItemTLV(arq, tipoDados, tamDados);

				bibliotecas ~= format("%s (%.2f KB)", nomeBib, tamDados / 1024.0);
				arq.seek(tamDados, SEEK_CUR);
			}
			else if (tipo == HarpyBinTipo.SECAO_BYTECODE)
			{
				tamanhoBytecode = tamanho;

				ubyte[4] countBuf;
				arq.rawRead(countBuf);
				numInstrucoes = littleEndianToNative!uint(countBuf);
				arq.seek(tamanho - 4, SEEK_CUR);
			}
			else
				arq.seek(tamanho, SEEK_CUR);
		}

		if (temMetadados)
		{
			writeln("\n--- Metadados ---");
			if ("nome" in metadados)
				writefln("Nome: %s", metadados["nome"]);
			if ("versao" in metadados)
				writefln("Versão: %s", metadados["versao"]);
			if ("autor" in metadados)
				writefln("Autor: %s", metadados["autor"]);
			if ("data" in metadados)
				writefln("Data: %s", metadados["data"]);
			if ("descricao" in metadados && metadados["descricao"].length > 0)
				writefln("Descrição: %s", metadados["descricao"]);
		}

		if (numBibliotecas > 0)
		{
			writeln("\n--- Bibliotecas Incluídas ---");
			writefln("Total: %d (%.2f KB)", numBibliotecas, tamanhoBibliotecas / 1024.0);
			foreach (i, bib; bibliotecas)
				writefln("  %d. %s", i + 1, bib);
		}
	}
	catch (Exception e)
		sair(format("Erro ao ler arquivo '%s'.", e.msg));
}

void main(string[] argumentos)
{
	loadEnv();

	DiagnosticError erro = new DiagnosticError; // classe que gera os erros de todo o sistema
	Argumentos args;
	args.saida = "harpy.hvm"; // arquivo padrão caso nenhuma saída seja passada

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
			"info", &args.info,
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

		// verifica se foram passados argumentos
		// o argumentos[0] por padrão contem o nome do executavel que está sendo executado
		if (argumentos.length == 1)
			sair_("Era esperado um arquivo de extensão '.rp' como argumento.", 1);

		// introduzindo um novo recurso ja que criei um sistema para arquivos de configuração, suporte a comandos basicamente
		string comando = argumentos[1];
		bool eComando = false;
		string arquivo;

		if (exists(APP))
			projeto = carregarConfig();

		switch (comando)
		{
		case "compilar":
			arquivo = projeto.entrada;
			args.compilar = true;
			eComando = true;
			break;

		case "iniciar":
			writeln("projeto");
			return;

		default:
			// se não for um comando então só ignora e segue o resto
			arquivo = comando;
			break;
		}

		// verifica se o arquivo de configuração existe
		// vamos carregar ele se um comando foi "ativado"
		if (eComando)
		{
			projeto = carregarConfig();
			args.saida = projeto.compilacao.saida;
			args.otimizar = projeto.compilacao.otimizar;
			args.estatico = projeto.compilacao.estatico;
			args.semBiblioteca = projeto.compilacao.biblioteca_nativa ? false : true;
			args.importacoes = projeto.dependencias;
		}

		// arquivo aparentemente passado, vamos validar
		// é um arquivo ou existe?
		if (!exists(arquivo))
			sair(format("O arquivo '%s' não existe.", arquivo), 1);

		if (!isFile(arquivo))
			sair(format("'%s' não é um arquivo.", arquivo), 1);

		if (args.info)
		{
			if (extension(arquivo) != ".hvm")
				sair(format("Para usar a flag '%s' você deve fornecer um arquivo binário '.hvm'.", arquivo));
			info(arquivo);
			return;
		}

		// carrega bibliotecas externas, incluindo bibliotecas padrão da VM
		// bibliotecas do sistema ja estará pré carregadas
		string[] bibliotecasExternas;

		if (args.semBiblioteca == false)
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

			{
				void* handle = null;
				if (path !in bibliotecas)
					version (linux)
						handle = dlopen(path.toStringz, RTLD_LAZY | RTLD_NODELETE);

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
			compilarPrograma(instrucoes, args.saida, Tempo(args.tempo, tempoTotal, tempoLexer, tempoParser, tempoSA, tempoCG),
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
