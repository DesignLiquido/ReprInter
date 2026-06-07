module context;

import std.conv;
import errors;
import htype;
import token;
import utils;
import ast;

class ContextValue 
{
    HType type;
    Node value;
    bool isConst;

    this(HType type)
    {
        this.type = type;
    }

    void setValue(Node val, bool isConst = false)
    {
        this.isConst = isConst;
        this.value = val;
    }
}

class Context
{
private:
    Diagnostics err;
    // mapa de funções para salvar cada variavel de cada função
    // a ideia é validar a semantica durante o parser pra evitar um passe novo só pra resolver isso
    string fn; // função atual
    ContextValue[string][string] map;

public:
    this(Diagnostics err)
    {
        this.err = err;
    }

    bool setVar(string var, HType type)
    {
        if (varExists(var))
            return false;
        map[fn][var] = new ContextValue(type);
        return true;
    }

    bool setVarValue(Token var, Node value, bool isConst)
    {
        return setVarValue(dtostr(var.value.s), value, isConst);
    }

    bool setVarValue(string var, Node value, bool isConst)
    {
        if (!varExists(var))
            return false;
        map[fn][var].setValue(value, isConst);
        return true;
    }

    ContextValue* getVar(string var)
    {
        return var in map[fn];
    }

    bool varExists(string var)
    {
        return getVar(var) !is null;
    }

    string dtostr(dstring dstr)
    {
        return to!string(dstr);
    }

    bool trySetVar(Token tk, HType type)
    {
        string var = dtostr(tk.value.s);
        if (varExists(var))
        {
            err.error(tk.pos, "A variavel já existe.");
            err.report();
            hpy_erro("Erro");
        }
        setVar(var, type);
        return true;
    }

    ContextValue tryGetVar(Token tk)
    {
        string var = dtostr(tk.value.s);
        if (!varExists(var))
        {
            err.error(tk.pos, "A variavel não existe.");
            err.report();
            hpy_erro("Erro");
            return ContextValue.init;
        }
        return *getVar(var);
    }

    void setFn(Token name)
    {
        setFn(dtostr(name.value.s), name.pos);
    }

    void setFn(string name, Position pos)
    {
        if (name in map)
        {
            err.error(pos, "A função já existe.");
            err.report();
            hpy_erro("Erro");
            return;
        }
        map[fn] = (ContextValue[string]).init;
    }
}
