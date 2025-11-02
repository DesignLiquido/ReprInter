import std.stdio, std.file, std.path, std.array;
import frontend.lexer.token, frontend.lexer.lexer;
import erro;

void main(string[] argumentos)
{
	// ainda não temos suporte ao windows
	version (Windows)
	{
		writeln("Sem suporte ao windows ainda, apenas a sistemas Unix.");
		return;
	}

	// verifica se foram passados argumentos
	// o argumentos[0] por padrão contem o nome do executavel que está sendo executado
	if (argumentos.length == 1)
	{
		writeln("Era esperado um arquivo de extensão '.rp' como argumento.");
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

	DiagnosticError erro = new DiagnosticError; // classe que gera os erros de todo o sistema

	// lê o arquivo e pega o conteudo
	string conteudo = readText(arquivo);
	// passa o conteudo pro lexer pegando todos os tokens criados pelo lexer

	Token[] tokens = new Lexer(arquivo, conteudo, ".", erro).tokenize();

	if (erro.hasWarnings())
		erro.printDiagnostics();

	if (erro.hasErrors())
	{
		erro.printDiagnostics();
		return;
	}

	foreach (Token token; tokens)
		token.print();
}
