export enum HarpyTipo {
    String = "string",
    Int = "int",
    Vazio = "vazio",
}

export interface HarpyValor {
    valor: string;
    tipo: HarpyTipo;
}
