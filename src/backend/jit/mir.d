/**
 * mir.d — D bindings para a biblioteca MIR (vnmakarov/mir)
 *
 * Compile seu projeto com:
 *   ldc2 -betterC seu_arquivo.d mir.d -L-lmir -L-lm -L-ldl -L-lpthread
 *
 * ou linkando a libmir.a diretamente:
 *   ldc2 -betterC seu_arquivo.d mir.d /usr/local/lib/libmir.a -L-lm -L-ldl -L-lpthread
 */
module backend.jit.mir;

extern (C):

// =============================================================================
// mir-alloc.h
// =============================================================================

struct MIR_alloc
{
    void* function(void* alloc, size_t size) malloc;
    void* function(void* alloc, void* ptr, size_t size) realloc;
    void function(void* alloc, void* ptr) free;
    void* alloc_data;
}

alias MIR_alloc_t = MIR_alloc*;

// =============================================================================
// mir-code-alloc.h
// =============================================================================

struct MIR_code_alloc
{
    /* Opaque — usuário não precisa preencher; passe NULL para usar o padrão */
    void* _opaque;
}

alias MIR_code_alloc_t = MIR_code_alloc*;

// =============================================================================
// Tipos básicos  (mir.h)
// =============================================================================

alias MIR_scale_t = ubyte;
alias MIR_disp_t = long;
alias MIR_reg_t = uint;
alias MIR_alias_t = uint;
alias MIR_name_t = const(char)*;

enum MIR_MAX_SCALE = ubyte.max;
enum MIR_MAX_REG_NUM = uint.max;
enum MIR_NON_VAR = MIR_MAX_REG_NUM;

enum MIR_API_VERSION = 0.2;

// =============================================================================
// MIR_error_type_t
// =============================================================================

enum MIR_error_type_t : int
{
    MIR_no_error,
    MIR_syntax_error,
    MIR_binary_io_error,
    MIR_alloc_error,
    MIR_finish_error,
    MIR_no_module_error,
    MIR_nested_module_error,
    MIR_no_func_error,
    MIR_func_error,
    MIR_vararg_func_error,
    MIR_nested_func_error,
    MIR_wrong_param_value_error,
    MIR_hard_reg_error,
    MIR_reserved_name_error,
    MIR_import_export_error,
    MIR_undeclared_func_reg_error,
    MIR_repeated_decl_error,
    MIR_reg_type_error,
    MIR_wrong_type_error,
    MIR_unique_reg_error,
    MIR_undeclared_op_ref_error,
    MIR_ops_num_error,
    MIR_call_op_error,
    MIR_unspec_op_error,
    MIR_wrong_lref_error,
    MIR_ret_error,
    MIR_op_mode_error,
    MIR_out_op_error,
    MIR_invalid_insn_error,
    MIR_ctx_change_error,
}

alias MIR_error_func_t = void function(MIR_error_type_t error_type, const(char)* format, ...);

// =============================================================================
// MIR_insn_code_t
// =============================================================================

enum MIR_insn_code_t : int
{
    // Moves
    MIR_MOV,
    MIR_FMOV,
    MIR_DMOV,
    MIR_LDMOV,
    // Extensions
    MIR_EXT8,
    MIR_EXT16,
    MIR_EXT32,
    MIR_UEXT8,
    MIR_UEXT16,
    MIR_UEXT32,
    // Int <-> float conversions
    MIR_I2F,
    MIR_I2D,
    MIR_I2LD,
    MIR_UI2F,
    MIR_UI2D,
    MIR_UI2LD,
    MIR_F2I,
    MIR_D2I,
    MIR_LD2I,
    MIR_F2D,
    MIR_F2LD,
    MIR_D2F,
    MIR_D2LD,
    MIR_LD2F,
    MIR_LD2D,
    // Unary
    MIR_NEG,
    MIR_NEGS,
    MIR_FNEG,
    MIR_DNEG,
    MIR_LDNEG,
    MIR_ADDR,
    MIR_ADDR8,
    MIR_ADDR16,
    MIR_ADDR32,
    // Aritmética
    MIR_ADD,
    MIR_ADDS,
    MIR_FADD,
    MIR_DADD,
    MIR_LDADD,
    MIR_SUB,
    MIR_SUBS,
    MIR_FSUB,
    MIR_DSUB,
    MIR_LDSUB,
    MIR_MUL,
    MIR_MULS,
    MIR_FMUL,
    MIR_DMUL,
    MIR_LDMUL,
    MIR_DIV,
    MIR_DIVS,
    MIR_UDIV,
    MIR_UDIVS,
    MIR_FDIV,
    MIR_DDIV,
    MIR_LDDIV,
    MIR_MOD,
    MIR_MODS,
    MIR_UMOD,
    MIR_UMODS,
    // Lógica
    MIR_AND,
    MIR_ANDS,
    MIR_OR,
    MIR_ORS,
    MIR_XOR,
    MIR_XORS,
    MIR_LSH,
    MIR_LSHS,
    MIR_RSH,
    MIR_RSHS,
    MIR_URSH,
    MIR_URSHS,
    // Comparação
    MIR_EQ,
    MIR_EQS,
    MIR_FEQ,
    MIR_DEQ,
    MIR_LDEQ,
    MIR_NE,
    MIR_NES,
    MIR_FNE,
    MIR_DNE,
    MIR_LDNE,
    MIR_LT,
    MIR_LTS,
    MIR_ULT,
    MIR_ULTS,
    MIR_FLT,
    MIR_DLT,
    MIR_LDLT,
    MIR_LE,
    MIR_LES,
    MIR_ULE,
    MIR_ULES,
    MIR_FLE,
    MIR_DLE,
    MIR_LDLE,
    MIR_GT,
    MIR_GTS,
    MIR_UGT,
    MIR_UGTS,
    MIR_FGT,
    MIR_DGT,
    MIR_LDGT,
    MIR_GE,
    MIR_GES,
    MIR_UGE,
    MIR_UGES,
    MIR_FGE,
    MIR_DGE,
    MIR_LDGE,
    // Overflow
    MIR_ADDO,
    MIR_ADDOS,
    MIR_SUBO,
    MIR_SUBOS,
    MIR_MULO,
    MIR_MULOS,
    MIR_UMULO,
    MIR_UMULOS,
    // Branches
    MIR_JMP,
    MIR_BT,
    MIR_BTS,
    MIR_BF,
    MIR_BFS,
    MIR_BEQ,
    MIR_BEQS,
    MIR_FBEQ,
    MIR_DBEQ,
    MIR_LDBEQ,
    MIR_BNE,
    MIR_BNES,
    MIR_FBNE,
    MIR_DBNE,
    MIR_LDBNE,
    MIR_BLT,
    MIR_BLTS,
    MIR_UBLT,
    MIR_UBLTS,
    MIR_FBLT,
    MIR_DBLT,
    MIR_LDBLT,
    MIR_BLE,
    MIR_BLES,
    MIR_UBLE,
    MIR_UBLES,
    MIR_FBLE,
    MIR_DBLE,
    MIR_LDBLE,
    MIR_BGT,
    MIR_BGTS,
    MIR_UBGT,
    MIR_UBGTS,
    MIR_FBGT,
    MIR_DBGT,
    MIR_LDBGT,
    MIR_BGE,
    MIR_BGES,
    MIR_UBGE,
    MIR_UBGES,
    MIR_FBGE,
    MIR_DBGE,
    MIR_LDBGE,
    MIR_BO,
    MIR_UBO,
    MIR_BNO,
    MIR_UBNO,
    MIR_LADDR,
    MIR_JMPI,
    // Calls
    MIR_CALL,
    MIR_INLINE,
    MIR_JCALL,
    MIR_SWITCH,
    MIR_RET,
    MIR_JRET,
    // Misc
    MIR_ALLOCA,
    MIR_BSTART,
    MIR_BEND,
    MIR_VA_ARG,
    MIR_VA_BLOCK_ARG,
    MIR_VA_START,
    MIR_VA_END,
    MIR_LABEL,
    MIR_UNSPEC,
    MIR_PRSET,
    MIR_PRBEQ,
    MIR_PRBNE,
    MIR_USE,
    MIR_PHI,
    MIR_INVALID_INSN,
    MIR_INSN_BOUND,
}

// =============================================================================
// MIR_type_t
// =============================================================================

enum MIR_BLK_NUM = 5;

enum MIR_type_t : int
{
    MIR_T_I8,
    MIR_T_U8,
    MIR_T_I16,
    MIR_T_U16,
    MIR_T_I32,
    MIR_T_U32,
    MIR_T_I64,
    MIR_T_U64,
    MIR_T_F,
    MIR_T_D,
    MIR_T_LD,
    MIR_T_P,
    MIR_T_BLK,
    MIR_T_RBLK = MIR_T_BLK + MIR_BLK_NUM,
    MIR_T_UNDEF,
    MIR_T_BOUND,
}

bool MIR_int_type_p(MIR_type_t t) pure
{
    return (MIR_type_t.MIR_T_I8 <= t && t <= MIR_type_t.MIR_T_U64)
        || t == MIR_type_t.MIR_T_P;
}

bool MIR_fp_type_p(MIR_type_t t) pure
{
    return MIR_type_t.MIR_T_F <= t && t <= MIR_type_t.MIR_T_LD;
}

bool MIR_blk_type_p(MIR_type_t t) pure
{
    return MIR_type_t.MIR_T_BLK <= t && t < MIR_type_t.MIR_T_RBLK;
}

// =============================================================================
// Structs de operandos
// =============================================================================

struct MIR_mem_t
{
    ubyte       type;     // MIR_type_t : 8
    MIR_scale_t scale;    // ubyte
    ushort      _pad;     // alinha alias_ em offset 4
    MIR_alias_t alias_;
    MIR_alias_t nonalias;
    uint        nloc;
    MIR_reg_t   base;
    MIR_reg_t   index;
    MIR_disp_t  disp;
}

struct MIR_str_t
{
    size_t len;
    const(char)* s;
}

union MIR_imm_t
{
    long i;
    ulong u;
    float f;
    double d;
    real ld;
}

// Forward declarations (structs opacos)
struct MIR_insn;
struct MIR_item;
struct MIR_module;
struct MIR_context;

alias MIR_label_t = MIR_insn*;
alias MIR_item_t = MIR_item*;
alias MIR_module_t = MIR_module*;
alias MIR_context_t = MIR_context*;
alias MIR_insn_t = MIR_insn*;

// =============================================================================
// MIR_op_mode_t  e  MIR_op_t
// =============================================================================

enum MIR_op_mode_t : int
{
    MIR_OP_UNDEF,
    MIR_OP_REG,
    MIR_OP_VAR,
    MIR_OP_INT,
    MIR_OP_UINT,
    MIR_OP_FLOAT,
    MIR_OP_DOUBLE,
    MIR_OP_LDOUBLE,
    MIR_OP_REF,
    MIR_OP_STR,
    MIR_OP_MEM,
    MIR_OP_VAR_MEM,
    MIR_OP_LABEL,
    MIR_OP_BOUND,
}

union MIR_op_u
{
    MIR_reg_t reg;
    MIR_reg_t var;
    long i;
    ulong u;
    float f;
    double d;
    real ld;
    MIR_item_t ref_;
    MIR_str_t str;
    MIR_mem_t mem;
    MIR_mem_t var_mem;
    MIR_label_t label;
}

struct MIR_op_t
{
    void*   data;
    ubyte   mode;       // MIR_op_mode_t : 8
    ubyte   value_mode; // MIR_op_mode_t : 8
    ubyte[6] _pad;      // padding até offset 16
    MIR_op_u u;         // offset 16, 32 bytes
}

// =============================================================================
// MIR_var_t
// =============================================================================

struct MIR_var_t
{
    MIR_type_t type;
    const(char)* name;
    size_t size;
}

// =============================================================================
// MIR_val_t  (intérprete)
// =============================================================================

union MIR_val_t
{
    MIR_insn_code_t ic;
    void* a;
    long i;
    ulong u;
    float f;
    double d;
    real ld;
}

// =============================================================================
// MIR_item_type_t
// =============================================================================

enum MIR_item_type_t : int
{
    MIR_func_item,
    MIR_proto_item,
    MIR_import_item,
    MIR_export_item,
    MIR_forward_item,
    MIR_data_item,
    MIR_ref_data_item,
    MIR_lref_data_item,
    MIR_expr_data_item,
    MIR_bss_item,
}

// =============================================================================
// MIR_code_reloc_t
// =============================================================================

struct MIR_code_reloc_t
{
    size_t offset;
    const void* value;
}

// =============================================================================
// _MIR_arg_desc_t
// =============================================================================

struct _MIR_arg_desc_t
{
    MIR_type_t type;
    size_t size;
}

// =============================================================================
// API pública — mir.h
// =============================================================================

// Versão e inicialização
double _MIR_get_api_version();
MIR_context_t _MIR_init(MIR_alloc_t alloc, MIR_code_alloc_t code_alloc);

// Wrapper seguro (verifica versão)
MIR_context_t MIR_init2(MIR_alloc_t alloc, MIR_code_alloc_t code_alloc)
{
    import core.stdc.stdio : fprintf, stderr;
    import core.stdc.stdlib : exit;

    if (MIR_API_VERSION != _MIR_get_api_version())
    {
        fprintf(stderr, "mir.d: versão incompatível com a libmir instalada!\n");
        exit(1);
    }
    return _MIR_init(alloc, code_alloc);
}

MIR_context_t MIR_init()
{
    return MIR_init2(null, null);
}

void MIR_finish(MIR_context_t ctx);

// Módulos
MIR_module_t MIR_new_module(MIR_context_t ctx, const(char)* name);
void MIR_finish_module(MIR_context_t ctx);
void MIR_load_module(MIR_context_t ctx, MIR_module_t m);
void MIR_load_external(MIR_context_t ctx, const(char)* name, void* addr);
void MIR_link(MIR_context_t ctx,
    void function(MIR_context_t, MIR_item_t) set_interface,
    void* function(const(char)*) import_resolver);
MIR_item_t MIR_get_global_item(MIR_context_t ctx, const(char)* name);
void MIR_change_module_ctx(MIR_context_t old_ctx, MIR_module_t m, MIR_context_t new_ctx);

// Itens de módulo
MIR_item_t MIR_new_import(MIR_context_t ctx, const(char)* name);
MIR_item_t MIR_new_export(MIR_context_t ctx, const(char)* name);
MIR_item_t MIR_new_forward(MIR_context_t ctx, const(char)* name);
MIR_item_t MIR_new_bss(MIR_context_t ctx, const(char)* name, size_t len);
MIR_item_t MIR_new_data(MIR_context_t ctx, const(char)* name,
    MIR_type_t el_type, size_t nel, const void* els);
MIR_item_t MIR_new_string_data(MIR_context_t ctx, const(char)* name, MIR_str_t str);
MIR_item_t MIR_new_ref_data(MIR_context_t ctx, const(char)* name,
    MIR_item_t item, long disp);
MIR_item_t MIR_new_lref_data(MIR_context_t ctx, const(char)* name,
    MIR_label_t label, MIR_label_t label2, long disp);
MIR_item_t MIR_new_expr_data(MIR_context_t ctx, const(char)* name, MIR_item_t expr_item);

// Protótipos
MIR_item_t MIR_new_proto_arr(MIR_context_t ctx, const(char)* name,
    size_t nres, MIR_type_t* res_types,
    size_t nargs, MIR_var_t* vars);
MIR_item_t MIR_new_proto(MIR_context_t ctx, const(char)* name,
    size_t nres, MIR_type_t* res_types, size_t nargs, ...);
MIR_item_t MIR_new_vararg_proto_arr(MIR_context_t ctx, const(char)* name,
    size_t nres, MIR_type_t* res_types,
    size_t nargs, MIR_var_t* vars);
MIR_item_t MIR_new_vararg_proto(MIR_context_t ctx, const(char)* name,
    size_t nres, MIR_type_t* res_types, size_t nargs, ...);

// Funções
MIR_item_t MIR_new_func_arr(MIR_context_t ctx, const(char)* name,
    size_t nres, MIR_type_t* res_types,
    size_t nargs, MIR_var_t* vars);
MIR_item_t MIR_new_func(MIR_context_t ctx, const(char)* name,
    size_t nres, MIR_type_t* res_types, size_t nargs, ...);
MIR_item_t MIR_new_vararg_func_arr(MIR_context_t ctx, const(char)* name,
    size_t nres, MIR_type_t* res_types,
    size_t nargs, MIR_var_t* vars);
MIR_item_t MIR_new_vararg_func(MIR_context_t ctx, const(char)* name,
    size_t nres, MIR_type_t* res_types, size_t nargs, ...);
void MIR_finish_func(MIR_context_t ctx);
const(char)* MIR_item_name(MIR_context_t ctx, MIR_item_t item);

// Registradores
MIR_reg_t MIR_new_func_reg(MIR_context_t ctx, void* func, MIR_type_t type, const(char)* name);
MIR_reg_t MIR_new_global_func_reg(MIR_context_t ctx, void* func, MIR_type_t type,
    const(char)* name, const(char)* hard_reg_name);
MIR_reg_t MIR_reg(MIR_context_t ctx, const(char)* reg_name, void* func);
MIR_type_t MIR_reg_type(MIR_context_t ctx, MIR_reg_t reg, void* func);
const(char)* MIR_reg_name(MIR_context_t ctx, MIR_reg_t reg, void* func);
const(char)* MIR_reg_hard_reg_name(MIR_context_t ctx, MIR_reg_t reg, void* func);

// Alias de memória
const(char)* MIR_alias_name(MIR_context_t ctx, MIR_alias_t alias_);
MIR_alias_t MIR_alias(MIR_context_t ctx, const(char)* name);

// Construção de operandos
MIR_op_t MIR_new_reg_op(MIR_context_t ctx, MIR_reg_t reg);
MIR_op_t MIR_new_int_op(MIR_context_t ctx, long v);
MIR_op_t MIR_new_uint_op(MIR_context_t ctx, ulong v);
MIR_op_t MIR_new_float_op(MIR_context_t ctx, float v);
MIR_op_t MIR_new_double_op(MIR_context_t ctx, double v);
MIR_op_t MIR_new_ldouble_op(MIR_context_t ctx, real v);
MIR_op_t MIR_new_ref_op(MIR_context_t ctx, MIR_item_t item);
MIR_op_t MIR_new_str_op(MIR_context_t ctx, MIR_str_t str);
MIR_op_t MIR_new_mem_op(MIR_context_t ctx, MIR_type_t type, MIR_disp_t disp,
    MIR_reg_t base, MIR_reg_t index, MIR_scale_t scale);
MIR_op_t MIR_new_alias_mem_op(MIR_context_t ctx, MIR_type_t type, MIR_disp_t disp,
    MIR_reg_t base, MIR_reg_t index, MIR_scale_t scale,
    MIR_alias_t alias_, MIR_alias_t noalias);
MIR_op_t MIR_new_label_op(MIR_context_t ctx, MIR_label_t label);
int MIR_op_eq_p(MIR_context_t ctx, MIR_op_t op1, MIR_op_t op2);

// Instruções
MIR_insn_t MIR_new_insn_arr(MIR_context_t ctx, MIR_insn_code_t code,
    size_t nops, MIR_op_t* ops);
MIR_insn_t MIR_new_insn(MIR_context_t ctx, MIR_insn_code_t code, ...);
MIR_insn_t MIR_new_call_insn(MIR_context_t ctx, size_t nops, ...);
MIR_insn_t MIR_new_jcall_insn(MIR_context_t ctx, size_t nops, ...);
MIR_insn_t MIR_new_ret_insn(MIR_context_t ctx, size_t nops, ...);
MIR_insn_t MIR_copy_insn(MIR_context_t ctx, MIR_insn_t insn);
MIR_insn_t MIR_new_label(MIR_context_t ctx);
const(char)* MIR_insn_name(MIR_context_t ctx, MIR_insn_code_t code);
size_t MIR_insn_nops(MIR_context_t ctx, MIR_insn_t insn);
MIR_op_mode_t MIR_insn_op_mode(MIR_context_t ctx, MIR_insn_t insn, size_t nop, int* out_p);
MIR_insn_code_t MIR_reverse_branch_code(MIR_insn_code_t code);

// Inserção/remoção de instruções
void MIR_append_insn(MIR_context_t ctx, MIR_item_t func, MIR_insn_t insn);
void MIR_prepend_insn(MIR_context_t ctx, MIR_item_t func, MIR_insn_t insn);
void MIR_insert_insn_after(MIR_context_t ctx, MIR_item_t func,
    MIR_insn_t after, MIR_insn_t insn);
void MIR_insert_insn_before(MIR_context_t ctx, MIR_item_t func,
    MIR_insn_t before, MIR_insn_t insn);
void MIR_remove_insn(MIR_context_t ctx, MIR_item_t func, MIR_insn_t insn);

// Output / debug
const(char)* MIR_type_str(MIR_context_t ctx, MIR_type_t tp);
void MIR_output_op(MIR_context_t ctx, void* f, MIR_op_t op, void* func);
void MIR_output_insn(MIR_context_t ctx, void* f, MIR_insn_t insn,
    void* func, int newline_p);
void MIR_output_item(MIR_context_t ctx, void* f, MIR_item_t item);
void MIR_output_module(MIR_context_t ctx, void* f, MIR_module_t module_);
void MIR_output(MIR_context_t ctx, void* f);

// I/O binário (disponível quando MIR_NO_IO == 0)
void MIR_write(MIR_context_t ctx, void* f);
void MIR_write_module(MIR_context_t ctx, void* f, MIR_module_t module_);
void MIR_read(MIR_context_t ctx, void* f);

// Scan de texto MIR
void MIR_scan_string(MIR_context_t ctx, const(char)* str);

// Erro
MIR_error_func_t MIR_get_error_func(MIR_context_t ctx);
void MIR_set_error_func(MIR_context_t ctx, MIR_error_func_t func);
MIR_alloc_t MIR_get_alloc(MIR_context_t ctx);
int MIR_get_func_redef_permission_p(MIR_context_t ctx);
void MIR_set_func_redef_permission(MIR_context_t ctx, int flag_p);

// =============================================================================
// Intérprete
// =============================================================================

void MIR_interp(MIR_context_t ctx, MIR_item_t func_item,
    MIR_val_t* results, size_t nargs, ...);
void MIR_interp_arr(MIR_context_t ctx, MIR_item_t func_item,
    MIR_val_t* results, size_t nargs, MIR_val_t* vals);
void MIR_set_interp_interface(MIR_context_t ctx, MIR_item_t func_item);

// =============================================================================
// mir-gen.h  (geração de código nativo / JIT)
// =============================================================================

void MIR_gen_init(MIR_context_t ctx);
void MIR_gen_set_debug_file(MIR_context_t ctx, void* f);      // sem gen_num
void MIR_gen_set_debug_level(MIR_context_t ctx, int debug_level); // sem gen_num
void MIR_gen_set_optimize_level(MIR_context_t ctx, uint level);
void* MIR_gen(MIR_context_t ctx, MIR_item_t func_item);       // sem gen_num
void MIR_gen_finish(MIR_context_t ctx);
void MIR_set_gen_interface(MIR_context_t ctx, MIR_item_t func_item);
void MIR_set_parallel_gen_interface(MIR_context_t ctx, MIR_item_t func_item);
void MIR_set_lazy_gen_interface(MIR_context_t ctx, MIR_item_t func_item);

// =============================================================================
// Helpers inline para predicados de instrução
// =============================================================================

bool MIR_call_code_p(MIR_insn_code_t code) pure
{
    return code == MIR_insn_code_t.MIR_CALL
        || code == MIR_insn_code_t.MIR_INLINE
        || code == MIR_insn_code_t.MIR_JCALL;
}

bool MIR_branch_code_p(MIR_insn_code_t code) pure
{
    return code == MIR_insn_code_t.MIR_JMP
        || MIR_int_branch_code_p(code)
        || MIR_FP_branch_code_p(code);
}

bool MIR_int_branch_code_p(MIR_insn_code_t code) pure
{
    with (MIR_insn_code_t)
        return code == MIR_BT || code == MIR_BTS || code == MIR_BF || code == MIR_BFS
            || code == MIR_BEQ || code == MIR_BEQS || code == MIR_BNE || code == MIR_BNES
            || code == MIR_BLT || code == MIR_BLTS || code == MIR_UBLT || code == MIR_UBLTS
            || code == MIR_BLE || code == MIR_BLES || code == MIR_UBLE || code == MIR_UBLES
            || code == MIR_BGT || code == MIR_BGTS || code == MIR_UBGT || code == MIR_UBGTS
            || code == MIR_BGE || code == MIR_BGES || code == MIR_UBGE || code == MIR_UBGES
            || code == MIR_BO || code == MIR_UBO || code == MIR_BNO || code == MIR_UBNO;
}

bool MIR_FP_branch_code_p(MIR_insn_code_t code) pure
{
    with (MIR_insn_code_t)
        return code == MIR_FBEQ || code == MIR_DBEQ || code == MIR_LDBEQ
            || code == MIR_FBNE || code == MIR_DBNE || code == MIR_LDBNE
            || code == MIR_FBLT || code == MIR_DBLT || code == MIR_LDBLT
            || code == MIR_FBLE || code == MIR_DBLE || code == MIR_LDBLE
            || code == MIR_FBGT || code == MIR_DBGT || code == MIR_LDBGT
            || code == MIR_FBGE || code == MIR_DBGE || code == MIR_LDBGE;
}

struct MIR_func_desc;
alias MIR_func_t = MIR_func_desc*;

// Corrige as assinaturas que estavam com void*
MIR_func_t MIR_get_item_func(MIR_context_t ctx, MIR_item_t item);
MIR_reg_t  MIR_new_func_reg(MIR_context_t ctx, MIR_func_t func, MIR_type_t type, const(char)* name);
MIR_reg_t  MIR_reg(MIR_context_t ctx, const(char)* reg_name, MIR_func_t func);
MIR_type_t MIR_reg_type(MIR_context_t ctx, MIR_reg_t reg, MIR_func_t func);
const(char)* MIR_reg_name(MIR_context_t ctx, MIR_reg_t reg, MIR_func_t func);
const(char)* MIR_reg_hard_reg_name(MIR_context_t ctx, MIR_reg_t reg, MIR_func_t func);
