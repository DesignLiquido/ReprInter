export default class HarpyContadorTemporario {
    contador: number = 0;
    proximo(): number {
        return this.contador++;
    }
}
