module stdlib.matematica;

import stdlib_base;
import core.stdc.stdio;
import core.stdc.math;

extern (C):

Value PI(Params* params)
{
    return makeFloat(3.14159265358979323846);
}

Value E(Params* params)
{
    return makeFloat(2.71828182845904523536);
}

Value arredondar(Params* params)
{
    if (params.argc == 0)
        return makeFloat(0.0);

    Value arg = params.args[0];
    verificarTipo(Type.Float, arg.type);

    return makeFloat(core.stdc.math.round(arg.value.f64));
}
