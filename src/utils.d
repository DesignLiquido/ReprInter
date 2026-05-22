module utils;

public import core.stdc.stdio;
public import core.stdc.stdlib;
public import flib.arena;

static Arena* GLOBAL_ARENA = null;

void hvmAssert(bool cond, string msg)
{
    if (cond) return;
    if (GLOBAL_ARENA) GLOBAL_ARENA.destruct();
    printf("Assert: %s\n", cast(char*) msg);
    exit(1);
}
