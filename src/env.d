module env;

import std.stdio, std.file, std.path, std.process, core.stdc.stdlib : exit;

string HOME, MAIN_DIR, DIR_LIBS, DIR_STD, DIR_BIN;

void loadEnv()
{
    version (linux)
    {
        HOME = environment.get("HOME");
        MAIN_DIR = HOME ~ "/.harpy/";
        DIR_LIBS = MAIN_DIR ~ "libs/";
        DIR_STD = MAIN_DIR ~ "biblioteca/";
        // cria o diretório padrão em ~/.harpy/
        if (!exists(MAIN_DIR))
            mkdir(MAIN_DIR);
        // cria o diretório padrão em ~/.harpy/libs/
        if (!exists(DIR_LIBS))
            mkdir(DIR_LIBS);
        if (!exists(DIR_STD))
            mkdir(DIR_STD);
    }
    else version (Windows)
    {
        // suporte parcial
        // caracteres especiais podem ser imprimidos de forma incorreta
        // preciso testar muitos casos ainda, além do sistema de arquivos que necessitará
        // além disso, será preciso criar um instalador pro Windows
        // ele irá baixar alguma release pelo github, extrair o binario apenas e setar o PATH corretamente
        // não sei muito sobre instaladores do windows então se eu puder embutir o binario no instalador então assim farei
        import core.sys.windows.windows;

        writeln("AVISO: O windows possui suporte parcial.");
        SetConsoleOutputCP(65_001);
        SetConsoleCP(65_001);
        // vou dar a saida precoce pois sei que o suporte é inexistente
        exit(69);
    }
    else
    {
        writeln("Não há suporte para o seu sistema operacional.");
        exit(1);
    }

    // valida se alguma das variaveis importantes não foram definidas
    // deixei essa validação para suprir todos os casos de erros que podem vir a ocorrer
    if (!exists(MAIN_DIR) || !exists(DIR_LIBS) || !exists(HOME) || !exists(DIR_STD))
    {
        writeln(
            "Houve um erro ao definir algumas variaveis globais, crie um ISSUE no repositório.");
        exit(1);
    }
}
