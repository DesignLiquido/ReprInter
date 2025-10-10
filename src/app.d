import core.stdc.stdio, core.stdc.stdlib;
import vm;

extern (C)
int main()
{
	VM vm;

	// Exemplo 1: (9 + 60) * 2 = 138
	printf("=== Teste 1: (9 + 60) * 2 ===\n");
	int c1 = vm.addConstant(TypedValue.makeInt(9));
	int c2 = vm.addConstant(TypedValue.makeInt(60));
	int c3 = vm.addConstant(TypedValue.makeInt(2));

	vm.emit(OpCode.Push, c1);
	vm.emit(OpCode.Push, c2);
	vm.emit(OpCode.AddI32);
	vm.emit(OpCode.Push, c3);
	vm.emit(OpCode.MulI32);
	vm.emit(OpCode.PrintLn);
	vm.emit(OpCode.Halt);

	vm.run();

	// Exemplo 2: Comparação e lógica
	printf("\n=== Teste 2: 10 > 5 ===\n");
	VM vm2;
	int d1 = vm2.addConstant(TypedValue.makeInt(10));
	int d2 = vm2.addConstant(TypedValue.makeInt(5));

	vm2.emit(OpCode.Push, d1);
	vm2.emit(OpCode.Push, d2);
	vm2.emit(OpCode.GtI32);
	vm2.emit(OpCode.PrintLn);
	vm2.emit(OpCode.Halt);

	vm2.run();

	// Exemplo 3: Jump condicional (simples if)
	printf("\n=== Teste 3: If 5 < 10 então print 999 ===\n");
	VM vm3;
	int e1 = vm3.addConstant(TypedValue.makeInt(5));
	int e2 = vm3.addConstant(TypedValue.makeInt(10));
	int e3 = vm3.addConstant(TypedValue.makeInt(999));

	vm3.emit(OpCode.Push, e1); // 0
	vm3.emit(OpCode.Push, e2); // 1
	vm3.emit(OpCode.LtI32); // 2
	vm3.emit(OpCode.JumpIfFalse, 6); // 3 - se falso, pula para 6 (Halt)
	vm3.emit(OpCode.Push, e3); // 4
	vm3.emit(OpCode.PrintLn); // 5
	vm3.emit(OpCode.Halt); // 6

	vm3.run();

	return 0;
}
