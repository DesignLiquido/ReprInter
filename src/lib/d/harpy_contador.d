module lib.d.harpy_contador;

class HarpyContadorTemporario
{
public:
    long contador = 0;
    long proximo()
    {
        return this.contador++;
    }
}
