/*
 * Referencia legivel do programa executado por rv32i_system_program.s.
 *
 * Este arquivo descreve os mesmos algoritmos e resultados, mas o HEX oficial
 * e produzido pelo gerador explicito de Assembly. Assim, nenhuma escolha de
 * compilador, biblioteca ou pseudo-instrucao entra no teste do processador.
 */
#include <stdint.h>

#define WORD_AT(address) (*(volatile int32_t *)(uintptr_t)(address))
#define UWORD_AT(address) (*(volatile uint32_t *)(uintptr_t)(address))

#define A_BASE       0x100u
#define B_BASE       0x120u
#define RESULT_BASE  0x180u
#define SCRATCH_BASE 0x1b0u

#define PASS_STATUS  0x600d600du
#define FAIL_STATUS  0xbad0bad0u
#define PC_PROBE_PC  0x000005d4u

static int sum_array(volatile int32_t *v, int n)
{
    int sum = 0;
    int i;

    for (i = 0; i < n; ++i)
        sum += v[i];
    return sum;
}

static void minmax(volatile int32_t *v, int n, int *minimum, int *maximum)
{
    int min_value = v[0];
    int max_value = v[0];
    int i;

    for (i = 1; i < n; ++i) {
        if (v[i] < min_value)
            min_value = v[i];
        if (v[i] >= max_value)
            max_value = v[i];
    }
    *minimum = min_value;
    *maximum = max_value;
}

static int abs32(int value)
{
    return (value < 0) ? -value : value;
}

/* Multiplicacao didatica por somas sucessivas; nao depende da extensao M. */
static int mul_signed(int left, int right)
{
    int negative = (left < 0) ^ (right < 0);
    int magnitude_left = abs32(left);
    int magnitude_right = abs32(right);
    int result = 0;

    while (magnitude_right != 0) {
        result += magnitude_left;
        --magnitude_right;
    }
    return negative ? -result : result;
}

static int dot_product(volatile int32_t *a, volatile int32_t *b, int n)
{
    int result = 0;
    int i;

    for (i = 0; i < n; ++i)
        result += mul_signed(a[i], b[i]);
    return result;
}

static void insertion_sort(volatile int32_t *v, int n)
{
    int i;

    for (i = 1; i < n; ++i) {
        int key = v[i];
        int j = i - 1;

        while ((j >= 0) && (v[j] > key)) {
            v[j + 1] = v[j];
            --j;
        }
        v[j + 1] = key;
    }
}

static int binary_search_recursive(volatile int32_t *v, int lo, int hi,
                                   int target)
{
    int middle;
    int value;

    if (lo > hi)
        return -1;

    middle = lo + ((hi - lo) >> 1);
    value = v[middle];
    if (value == target)
        return middle;
    if (value < target)
        return binary_search_recursive(v, middle + 1, hi, target);
    return binary_search_recursive(v, lo, middle - 1, target);
}

static uint32_t checksum8(volatile int32_t *v, int bytes)
{
    volatile uint8_t *data = (volatile uint8_t *)v;
    uint32_t checksum = 0;
    int i;

    for (i = 0; i < bytes; ++i)
        checksum ^= data[i];
    return checksum;
}

static uint32_t memory_probe(void)
{
    volatile uint8_t *bytes = (volatile uint8_t *)(uintptr_t)SCRATCH_BASE;
    volatile uint16_t *halves = (volatile uint16_t *)(uintptr_t)(SCRATCH_BASE + 4u);

    bytes[0] = 0x01u;
    bytes[1] = 0x7fu;
    bytes[2] = 0xffu;
    bytes[3] = 0x80u;
    if (UWORD_AT(SCRATCH_BASE) != 0x80ff7f01u)
        return 0;
    if ((int8_t)bytes[3] != -128 || bytes[3] != 128u)
        return 0;

    halves[0] = 0x7fffu;
    halves[1] = 0x8001u;
    if ((int16_t)halves[1] != -32767 || halves[1] != 0x8001u)
        return 0;
    if (UWORD_AT(SCRATCH_BASE + 4u) != 0x80017fffu)
        return 0;
    return 0x135u;
}

static uint32_t branch_probe(void)
{
    int32_t negative_three = -3;
    int32_t seven = 7;
    uint32_t signature = 0;

    if (negative_three != seven) signature |= 1u;             /* BEQ/BNE */
    if (negative_three < seven) signature |= 2u;              /* BLT */
    if (seven >= negative_three) signature |= 4u;             /* BGE */
    if ((uint32_t)seven < (uint32_t)negative_three) signature |= 8u; /* BLTU */
    if ((uint32_t)negative_three >= (uint32_t)seven) signature |= 16u; /* BGEU */
    if (negative_three == negative_three) signature |= 32u;   /* BEQ */
    return signature;
}

static uint32_t alu_probe(void)
{
    uint32_t signature = 0;
    uint32_t value = 5u;
    uint32_t negative_sixteen = 0xfffffff0u;
    uint32_t three = 3u;

#define MIX(x) do { signature ^= (uint32_t)(x); } while (0)
    MIX(value);                         /* ADDI */
    value <<= 2; MIX(value);            /* SLLI */
    MIX(((int32_t)negative_sixteen < 0) ? 1u : 0u); /* SLTI */
    MIX((negative_sixteen < 1u) ? 1u : 0u);         /* SLTIU */
    value ^= 0x55u; MIX(value);         /* XORI */
    MIX(negative_sixteen >> 2);         /* SRLI */
    MIX((uint32_t)((int32_t)negative_sixteen >> 2)); /* SRAI */
    value |= 0x100u; MIX(value);        /* ORI */
    value &= 0xffu; MIX(value);         /* ANDI */
    MIX(negative_sixteen + three);      /* ADD */
    MIX(three - negative_sixteen);      /* SUB */
    MIX(three << three);                /* SLL */
    MIX(((int32_t)negative_sixteen < (int32_t)three) ? 1u : 0u); /* SLT */
    MIX((negative_sixteen < three) ? 1u : 0u);                   /* SLTU */
    MIX(negative_sixteen ^ three);      /* XOR */
    MIX(negative_sixteen >> three);     /* SRL */
    MIX((uint32_t)((int32_t)negative_sixteen >> three)); /* SRA */
    MIX(negative_sixteen | three);      /* OR */
    MIX(negative_sixteen & three);      /* AND */
    MIX(123u);                          /* WB -> Decode marker */
    MIX(2u);                            /* dependent ADDI marker */
#undef MIX
    return signature;
}

/* No Assembly, AUIPC a0,0 retorna diretamente o PC 0x5d4 desta rotina. */
static uint32_t pc_probe_reference(void)
{
    return PC_PROBE_PC;
}

static int run_suite(void)
{
    volatile int32_t *a = (volatile int32_t *)(uintptr_t)A_BASE;
    volatile int32_t *b = (volatile int32_t *)(uintptr_t)B_BASE;
    int minimum;
    int maximum;

    a[0] = 7; a[1] = -3; a[2] = 12; a[3] = 4;
    b[0] = 2; b[1] = 5; b[2] = -1; b[3] = 6;

    WORD_AT(RESULT_BASE + 0x00u) = sum_array(a, 4);
    WORD_AT(RESULT_BASE + 0x2cu) = WORD_AT(RESULT_BASE + 0x00u);
    minmax(a, 4, &minimum, &maximum);
    WORD_AT(RESULT_BASE + 0x04u) = minimum;
    WORD_AT(RESULT_BASE + 0x08u) = maximum;
    WORD_AT(RESULT_BASE + 0x14u) = dot_product(a, b, 4);

    insertion_sort(a, 4);
    WORD_AT(RESULT_BASE + 0x0cu) = binary_search_recursive(a, 0, 3, 12);
    WORD_AT(RESULT_BASE + 0x10u) = binary_search_recursive(a, 0, 3, 5);
    WORD_AT(RESULT_BASE + 0x18u) = (int32_t)checksum8(a, 16);
    WORD_AT(RESULT_BASE + 0x24u) = (int32_t)memory_probe();
    WORD_AT(RESULT_BASE + 0x1cu) = (int32_t)branch_probe();
    WORD_AT(RESULT_BASE + 0x20u) = (int32_t)alu_probe();
    WORD_AT(RESULT_BASE + 0x28u) = (int32_t)pc_probe_reference();
    return 0;
}

static int verify_results(void)
{
    volatile int32_t *a = (volatile int32_t *)(uintptr_t)A_BASE;
    volatile int32_t *b = (volatile int32_t *)(uintptr_t)B_BASE;

    if (WORD_AT(0x180u) != 20) return 1;
    if (WORD_AT(0x184u) != -3) return 2;
    if (WORD_AT(0x188u) != 12) return 3;
    if (a[0] != -3 || a[1] != 4 || a[2] != 7 || a[3] != 12) return 4;
    if (WORD_AT(0x18cu) != 3) return 5;
    if (WORD_AT(0x190u) != -1) return 6;
    if (WORD_AT(0x194u) != 11) return 7;
    if (WORD_AT(0x198u) != 13) return 8;
    if (UWORD_AT(0x19cu) != 0x3fu) return 9;
    if (UWORD_AT(0x1a0u) != 0xdffffed1u) return 10;
    if (UWORD_AT(0x1a4u) != 0x135u) return 11;
    if (UWORD_AT(0x1a8u) != PC_PROBE_PC) return 12;
    if (b[0] != 2 || b[1] != 5 || b[2] != -1 || b[3] != 6) return 14;
    if (WORD_AT(0x1acu) != 20) return 15;
    return 0;
}

int main(void)
{
    int error = run_suite();

    if (error != 0)
        return error;
    return verify_results();
}

/*
 * A versao Assembly fornece _start, inicializa sp=0x800, chama main, confere
 * a restauracao da pilha e escreve error/status. PASS_STATUS e FAIL_STATUS
 * ficam aqui como documentacao dos valores publicados em 0x1f0.
 */
