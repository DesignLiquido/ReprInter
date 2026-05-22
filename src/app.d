module app;

import harpyvm;
import utils;

extern(C) int main(int argc, char** args) 
{
    Arena arena = Arena(64);
    scope (exit) arena.destruct();
    GLOBAL_ARENA = &arena;

    uint len;
    uint* program = cast(uint*) arena.alloc(24);
    program[len++] = cast(uint)(HarpyOpCode.Halt);

    HarpyVirtualMachine hVirtualMachine = HarpyVirtualMachine(program, len);
    scope (exit) hVirtualMachine.destruct();
    
    hVirtualMachine.setup();
    hVirtualMachine.run();

    return 0;
}
