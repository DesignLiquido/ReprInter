import std.stdio, std.file, std.path, std.array;
import frontend.lexer.token, frontend.lexer.lexer;

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

	// lê o arquivo e pega o conteudo
	string conteudo = readText(arquivo);
	writeln(conteudo);
}
