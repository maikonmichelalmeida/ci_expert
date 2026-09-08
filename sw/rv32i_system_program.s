.section .text
.globl _start

# ------------------------------------------------------------
# _start: inicializacao bare-metal e publicacao atomica do status.
# sp comeca em 0x800; chama main; valida retorno e restauracao da stack.
# PASS/FAIL e a ultima escrita significativa antes do loop final.
# ------------------------------------------------------------
_start:
    lui sp,0x1                            # sp recebe 0x1000
    addi sp,sp,-2048                      # sp = 0x800
    sw zero,496(zero)                     # status inicial = 0
    sw zero,500(zero)                     # error inicial = 0
    jal ra,main                           # call main
    addi t0,a0,0                          # preserva codigo retornado por main
    sw sp,504(zero)                       # snapshot final do sp
    bne t0,zero,start_fail_code
    lui t1,0x1
    addi t1,t1,-2048                      # valor esperado de sp
    bne sp,t1,start_fail_stack
    sw zero,500(zero)                     # error=0 antes do status
    lui t2,0x600d6                        # assinatura PASS
    addi t2,t2,13                         # parte baixa
    sw t2,496(zero)                       # commit final de sucesso
    jal zero,done                         # jump done
start_fail_stack:
    addi t0,zero,13                       # erro 13: stack
start_fail_code:
    sw t0,500(zero)                       # publica o codigo antes do FAIL
    lui t2,0xbad0c                        # assinatura FAIL
    addi t2,t2,-1328                      # parte baixa
    sw t2,496(zero)                       # commit final de falha
done:
    jal zero,done                         # loop final observavel no waveform
# ------------------------------------------------------------
# int main(void)
# non-leaf; frame 16 bytes; salva ra em 12(sp).
# chama run_suite e verify_results; retorna codigo em a0.
# O epilogo cria deliberadamente LW ra -> JALR imediato.
# ------------------------------------------------------------
main:
    addi sp,sp,-16
    sw ra,12(sp)
    jal ra,run_suite                      # call run_suite
    bne a0,zero,main_return
    jal ra,verify_results                 # call verify_results
main_return:
    addi sp,sp,16                         # restaura sp antes de buscar ra
    lw ra,-4(sp)                          # ra salvo no antigo 12(sp)
    jalr zero,0(ra)                       # retorno imediato apos LOAD: exercita load-use JALR
# ------------------------------------------------------------
# int run_suite(void)
# non-leaf; frame 16 bytes; salva ra.
# Inicializa vetores, chama todas as rotinas e grava resultados.
# ------------------------------------------------------------
run_suite:
    addi sp,sp,-16
    sw ra,12(sp)
# A=[7,-3,12,4] e B=[2,5,-1,6], produzidos por software.
    addi t0,zero,7
    sw t0,256(zero)
    addi t0,zero,-3
    sw t0,260(zero)
    addi t0,zero,12
    sw t0,264(zero)
    addi t0,zero,4
    sw t0,268(zero)
    addi t0,zero,2
    sw t0,288(zero)
    addi t0,zero,5
    sw t0,292(zero)
    addi t0,zero,-1
    sw t0,296(zero)
    addi t0,zero,6
    sw t0,300(zero)
    addi a0,zero,256
    addi a1,zero,4
    jal ra,sum_array                      # call sum_array
    sw a0,384(zero)
load_store_copy_load:
    lw t0,384(zero)                       # resultado da soma
    sw t0,428(zero)                       # LOAD -> STORE.rs2 consecutivo: bypass tardio WB->MEM
    addi a0,zero,256
    addi a1,zero,4
    jal ra,minmax                         # call minmax
    sw a0,388(zero)
    sw a1,392(zero)
    addi a0,zero,256
    addi a1,zero,288
    addi a2,zero,4
    jal ra,dot_product                    # call dot_product
    sw a0,404(zero)
    addi a0,zero,256
    addi a1,zero,4
    jal ra,insertion_sort                 # call insertion_sort
    addi a0,zero,256
    addi a1,zero,0
    addi a2,zero,3
    addi a3,zero,12
    jal ra,binary_search_recursive        # call binary_search_recursive
    sw a0,396(zero)
    addi a0,zero,256
    addi a1,zero,0
    addi a2,zero,3
    addi a3,zero,5
    jal ra,binary_search_recursive        # call binary_search_recursive
    sw a0,400(zero)
    addi a0,zero,256
    addi a1,zero,16
    jal ra,checksum8                      # call checksum8
    sw a0,408(zero)
    addi a0,zero,432
    jal ra,memory_probe                   # call memory_probe
    sw a0,420(zero)
    jal ra,branch_probe                   # call branch_probe
    sw a0,412(zero)
    jal ra,alu_probe                      # call alu_probe
    sw a0,416(zero)
    jal ra,pc_probe                       # call pc_probe
    sw a0,424(zero)
    addi a0,zero,0                        # run_suite terminou
    addi sp,sp,16
    lw ra,-4(sp)
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# int sum_array(int *v, int n)
# leaf; sem frame; a0=v, a1=n; retorna soma em a0.
# LW seguido imediatamente por ADD cria load-use real.
# ------------------------------------------------------------
sum_array:
    addi t0,zero,0                        # sum=0
sum_array_loop:
    beq a1,zero,sum_array_done
    lw t1,0(a0)
    add t0,t0,t1                          # sum += *v (consumidor imediato)
    addi a0,a0,4
    addi a1,a1,-1
    jal zero,sum_array_loop               # jump sum_array_loop
sum_array_done:
    addi a0,t0,0
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# void minmax(int *v, int n), retorno a0=min e a1=max
# leaf; sem frame; BLT/BGE fazem comparacoes signed.
# ------------------------------------------------------------
minmax:
    lw t0,0(a0)
    addi t1,t0,0                          # min=v[0]
    addi t2,t0,0                          # max=v[0]
    addi a0,a0,4
    addi a1,a1,-1
minmax_loop:
    beq a1,zero,minmax_done
    lw t3,0(a0)
    blt t3,t1,minmax_set_min
    bge t3,t2,minmax_set_max
    jal zero,minmax_next                  # jump minmax_next
minmax_set_min:
    addi t1,t3,0
    jal zero,minmax_next                  # jump minmax_next
minmax_set_max:
    addi t2,t3,0
minmax_next:
    addi a0,a0,4
    addi a1,a1,-1
    jal zero,minmax_loop                  # jump minmax_loop
minmax_done:
    addi a0,t1,0
    addi a1,t2,0
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# int dot_product(int *a, int *b, int n)
# non-leaf; frame 32 bytes; salva ra,s0,s1,s2,s3.
# chama mul_signed a cada elemento e preserva ponteiros/contador.
# ------------------------------------------------------------
dot_product:
    addi sp,sp,-32
    sw ra,28(sp)
    sw s0,24(sp)
    sw s1,20(sp)
    sw s2,16(sp)
    sw s3,12(sp)
    addi s0,a0,0
    addi s1,a1,0
    addi s2,a2,0
    addi s3,zero,0
dot_product_loop:
    beq s2,zero,dot_product_done
    lw a0,0(s0)
    lw a1,0(s1)
    jal ra,mul_signed                     # call mul_signed
    add s3,s3,a0
    addi s0,s0,4
    addi s1,s1,4
    addi s2,s2,-1
    jal zero,dot_product_loop             # jump dot_product_loop
dot_product_done:
    addi a0,s3,0
    lw s3,12(sp)
    lw s2,16(sp)
    lw s1,20(sp)
    lw s0,24(sp)
    lw ra,28(sp)
    addi sp,sp,32
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# int mul_signed(int a, int b)
# non-leaf; frame 32 bytes; salva ra,s0,s1,s2,s3.
# chama abs32 duas vezes e multiplica por somas sucessivas.
# ------------------------------------------------------------
mul_signed:
    addi sp,sp,-32
    sw ra,28(sp)
    sw s0,24(sp)
    sw s1,20(sp)
    sw s2,16(sp)
    sw s3,12(sp)
    addi s0,a0,0
    addi s1,a1,0
    xor s2,s0,s1                          # bit de sinal do produto
    jal ra,abs32                          # call abs32
    addi s3,a0,0                          # abs(a)
    addi a0,s1,0
    jal ra,abs32                          # call abs32
    addi t0,a0,0                          # contador=abs(b)
    addi t1,zero,0                        # produto=0
mul_signed_loop:
    beq t0,zero,mul_signed_apply_sign
    add t1,t1,s3
    addi t0,t0,-1
    jal zero,mul_signed_loop              # jump mul_signed_loop
mul_signed_apply_sign:
    bge s2,zero,mul_signed_positive
    sub a0,zero,t1                        # reaplica sinal negativo
    jal zero,mul_signed_epilogue          # jump mul_signed_epilogue
mul_signed_positive:
    addi a0,t1,0
mul_signed_epilogue:
    lw s3,12(sp)
    lw s2,16(sp)
    lw s1,20(sp)
    lw s0,24(sp)
    lw ra,28(sp)
    addi sp,sp,32
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# int abs32(int x)
# leaf; sem frame; nao trata INT32_MIN por decisao desta experiencia.
# ------------------------------------------------------------
abs32:
    bge a0,zero,abs32_done
    sub a0,zero,a0
abs32_done:
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# void insertion_sort(int *v, int n)
# leaf; sem frame; ordena signed in-place e usa SLLI para index*4.
# ------------------------------------------------------------
insertion_sort:
    addi t0,zero,1                        # i=1
sort_outer:
    bge t0,a1,sort_done
    slli t1,t0,2
    add t1,a0,t1
    lw t2,0(t1)                           # key=v[i]
    addi t3,t0,-1                         # j=i-1
sort_inner:
    blt t3,zero,sort_insert
    slli t4,t3,2
    add t5,a0,t4
    lw t6,0(t5)
    bge t2,t6,sort_insert
    sw t6,4(t5)                           # v[j+1]=v[j]
    addi t3,t3,-1
    jal zero,sort_inner                   # jump sort_inner
sort_insert:
    addi t4,t3,1
    slli t4,t4,2
    add t5,a0,t4
    sw t2,0(t5)
    addi t0,t0,1
    jal zero,sort_outer                   # jump sort_outer
sort_done:
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# int binary_search_recursive(int *v,int lo,int hi,int target)
# recursive/non-leaf; frame 32 bytes; salva ra,s0,s1,s2,s3.
# Cada caminho recursivo usa JAL real; retorno usa JALR.
# ------------------------------------------------------------
binary_search_recursive:
    addi sp,sp,-32
    sw ra,28(sp)
    sw s0,24(sp)
    sw s1,20(sp)
    sw s2,16(sp)
    sw s3,12(sp)
    addi s0,a0,0
    addi s1,a1,0
    addi s2,a2,0
    addi s3,a3,0
    blt s2,s1,binary_not_found            # hi < lo
    add t0,s1,s2
    srli t0,t0,1                          # mid=(lo+hi)>>1
    slli t1,t0,2
    add t1,s0,t1
    lw t2,0(t1)
    beq t2,s3,binary_found                # load-use no branch
    blt t2,s3,binary_right
# Busca esquerda: [lo,mid-1].
    addi a0,s0,0
    addi a1,s1,0
    addi a2,t0,-1
    addi a3,s3,0
    jal ra,binary_search_recursive        # chamada recursiva esquerda
    jal zero,binary_epilogue              # jump binary_epilogue
binary_right:
    addi a0,s0,0
    addi a1,t0,1
    addi a2,s2,0
    addi a3,s3,0
    jal ra,binary_search_recursive        # chamada recursiva direita
    jal zero,binary_epilogue              # jump binary_epilogue
binary_found:
    addi a0,t0,0
    jal zero,binary_epilogue              # jump binary_epilogue
binary_not_found:
    addi a0,zero,-1
binary_epilogue:
    lw s3,12(sp)
    lw s2,16(sp)
    lw s1,20(sp)
    lw s0,24(sp)
    lw ra,28(sp)
    addi sp,sp,32
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# uint32_t checksum8(const int32_t *v, int bytes)
# leaf; percorre os 16 bytes little-endian com LBU e XOR.
# ------------------------------------------------------------
checksum8:
    addi t0,zero,0
checksum8_loop:
    beq a1,zero,checksum8_done
    lbu t1,0(a0)
    xor t0,t0,t1
    addi a0,a0,1
    addi a1,a1,-1
    jal zero,checksum8_loop               # jump checksum8_loop
checksum8_done:
    addi a0,t0,0
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# int memory_probe(uint8_t *scratch)
# leaf; monta palavras por SB/SH e valida LB/LBU/LH/LHU/LW.
# Retorna 0x135 em sucesso ou zero em falha.
# ------------------------------------------------------------
memory_probe:
    addi t0,zero,1
    sb t0,0(a0)
    addi t0,zero,127
    sb t0,1(a0)
    addi t0,zero,-1
    sb t0,2(a0)
    addi t0,zero,-128
    sb t0,3(a0)
    lw t1,0(a0)
    lui t2,0x80ff8
    addi t2,t2,-255                       # parte baixa
    bne t1,t2,memory_probe_fail
    lb t1,3(a0)
    addi t2,zero,-128
    bne t1,t2,memory_probe_fail
    lbu t1,3(a0)
    addi t2,zero,128
    bne t1,t2,memory_probe_fail
    lui t0,0x8
    addi t0,t0,-1                         # parte baixa
    sh t0,4(a0)
    lui t0,0x8
    addi t0,t0,1                          # parte baixa
    sh t0,6(a0)
    lh t1,6(a0)
    lui t2,0xffff8
    addi t2,t2,1                          # parte baixa
    bne t1,t2,memory_probe_fail
    lhu t1,6(a0)
    lui t2,0x8
    addi t2,t2,1                          # parte baixa
    bne t1,t2,memory_probe_fail
    lw t1,4(a0)
    lui t2,0x80018
    addi t2,t2,-1                         # parte baixa
    bne t1,t2,memory_probe_fail
    addi a0,zero,309
    jalr zero,0(ra)                       # return
memory_probe_fail:
    addi a0,zero,0
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# uint32_t branch_probe(void)
# leaf; exercita BEQ/BNE/BLT/BGE/BLTU/BGEU.
# -3 < 7 signed, mas 0xfffffffd >= 7 unsigned; assinatura=0x3f.
# ------------------------------------------------------------
branch_probe:
    addi t0,zero,0
    addi t1,zero,-3
    addi t2,zero,7
    beq t1,t2,branch_probe_fail           # BEQ nao tomado
    beq t1,t1,branch_beq_ok               # BEQ tomado
    jal zero,branch_probe_fail            # jump branch_probe_fail
branch_beq_ok:
    ori t0,t0,1
    bne t1,t1,branch_probe_fail           # BNE nao tomado
    bne t1,t2,branch_bne_ok               # BNE tomado
    jal zero,branch_probe_fail            # jump branch_probe_fail
branch_bne_ok:
    ori t0,t0,2
    blt t1,t2,branch_blt_ok
    jal zero,branch_probe_fail            # jump branch_probe_fail
branch_blt_ok:
    ori t0,t0,4
    bge t2,t1,branch_bge_ok
    jal zero,branch_probe_fail            # jump branch_probe_fail
branch_bge_ok:
    ori t0,t0,8
    bltu t2,t1,branch_bltu_ok
    jal zero,branch_probe_fail            # jump branch_probe_fail
branch_bltu_ok:
    ori t0,t0,16
    bgeu t1,t2,branch_bgeu_ok
    jal zero,branch_probe_fail            # jump branch_probe_fail
branch_bgeu_ok:
    ori a0,t0,32
    jalr zero,0(ra)                       # return
branch_probe_fail:
    addi a0,zero,0
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# uint32_t alu_probe(void)
# leaf; cada resultado participa da assinatura ou de um check.
# Cobre as nove OP-IMM e as dez OP, incluindo signed/unsigned e SRL/SRA.
# ------------------------------------------------------------
alu_probe:
    addi t0,zero,0                        # assinatura
    addi t1,zero,-16
    addi t2,zero,3
    addi t3,zero,5
    xor t0,t0,t3
    slli t3,t3,2
    xor t0,t0,t3
    slti t4,t1,0
    xor t0,t0,t4
    sltiu t4,t1,1
    bne t4,zero,alu_probe_fail
    xor t0,t0,t4
    xori t3,t3,85
    xor t0,t0,t3
    srli t4,t1,2
    xor t0,t0,t4
    srai t5,t1,2
    xor t0,t0,t5
    ori t3,t3,256
    xor t0,t0,t3
    andi t3,t3,255
    xor t0,t0,t3
    add t3,t1,t2
    xor t0,t0,t3
    sub t3,t2,t1
    xor t0,t0,t3
    sll t3,t2,t2
    xor t0,t0,t3
    slt t3,t1,t2
    xor t0,t0,t3
    sltu t3,t1,t2
    bne t3,zero,alu_probe_fail
    xor t0,t0,t3
    xor t3,t1,t2
    xor t0,t0,t3
    srl t3,t1,t2
    xor t0,t0,t3
    sra t3,t1,t2
    xor t0,t0,t3
    or t3,t1,t2
    xor t0,t0,t3
    and t3,t1,t2
    bne t3,zero,alu_probe_fail
    xor t0,t0,t3
# Distancia de tres instrucoes: t4 chega a WB quando o XOR o le em Decode.
    addi t4,zero,123
    addi t5,zero,1
    addi t5,t5,1
    xor t0,t0,t4                          # WB -> Decode funcional
    xor t0,t0,t5
    addi a0,t0,0
    jalr zero,0(ra)                       # return
alu_probe_fail:
    addi a0,zero,0
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# uint32_t pc_probe(void)
# leaf; AUIPC com imediato zero retorna o PC da propria instrucao.
# ------------------------------------------------------------
pc_probe:
pc_probe_auipc:
    auipc a0,0x0                          # a0 = PC desta instrucao
    jalr zero,0(ra)                       # return
# ------------------------------------------------------------
# int verify_results(void)
# leaf; sem frame; confere resultados produzidos pelo proprio software.
# Retorna 0 ou codigo de erro especifico em a0.
# ------------------------------------------------------------
verify_results:
    lw t0,384(zero)                       # sum
    addi t1,zero,20
    bne t0,t1,verify_error_1
    lw t0,388(zero)                       # min
    addi t1,zero,-3
    bne t0,t1,verify_error_2
    lw t0,392(zero)                       # max
    addi t1,zero,12
    bne t0,t1,verify_error_3
    lw t0,256(zero)                       # A[0]
    addi t1,zero,-3
    bne t0,t1,verify_error_4
    lw t0,260(zero)                       # A[1]
    addi t1,zero,4
    bne t0,t1,verify_error_4
    lw t0,264(zero)                       # A[2]
    addi t1,zero,7
    bne t0,t1,verify_error_4
    lw t0,268(zero)                       # A[3]
    addi t1,zero,12
    bne t0,t1,verify_error_4
    lw t0,396(zero)                       # busca encontrada
    addi t1,zero,3
    bne t0,t1,verify_error_5
    lw t0,400(zero)                       # busca ausente
    addi t1,zero,-1
    bne t0,t1,verify_error_6
    lw t0,404(zero)                       # dot product
    addi t1,zero,11
    bne t0,t1,verify_error_7
    lw t0,408(zero)                       # checksum
    addi t1,zero,13
    bne t0,t1,verify_error_8
    lw t0,412(zero)                       # branch signature
    addi t1,zero,63
    bne t0,t1,verify_error_9
    lw t0,416(zero)                       # ALU signature
    lui t1,0xe0000
    addi t1,t1,-303                       # parte baixa
    bne t0,t1,verify_error_10
    lw t0,420(zero)                       # memory signature
    addi t1,zero,309
    bne t0,t1,verify_error_11
    lw t0,424(zero)                       # pc_probe
    addi t1,zero,1492                     # PC esperado pelo mapa
    bne t0,t1,verify_error_12
    lw t0,288(zero)                       # B[0]
    addi t1,zero,2
    bne t0,t1,verify_error_14
    lw t0,292(zero)                       # B[1]
    addi t1,zero,5
    bne t0,t1,verify_error_14
    lw t0,296(zero)                       # B[2]
    addi t1,zero,-1
    bne t0,t1,verify_error_14
    lw t0,300(zero)                       # B[3]
    addi t1,zero,6
    bne t0,t1,verify_error_14
    lw t0,428(zero)                       # copia LOAD->STORE
    addi t1,zero,20
    bne t0,t1,verify_error_15
    addi a0,zero,0
    jalr zero,0(ra)                       # return
verify_error_1:
    addi a0,zero,1
    jalr zero,0(ra)                       # return
verify_error_2:
    addi a0,zero,2
    jalr zero,0(ra)                       # return
verify_error_3:
    addi a0,zero,3
    jalr zero,0(ra)                       # return
verify_error_4:
    addi a0,zero,4
    jalr zero,0(ra)                       # return
verify_error_5:
    addi a0,zero,5
    jalr zero,0(ra)                       # return
verify_error_6:
    addi a0,zero,6
    jalr zero,0(ra)                       # return
verify_error_7:
    addi a0,zero,7
    jalr zero,0(ra)                       # return
verify_error_8:
    addi a0,zero,8
    jalr zero,0(ra)                       # return
verify_error_9:
    addi a0,zero,9
    jalr zero,0(ra)                       # return
verify_error_10:
    addi a0,zero,10
    jalr zero,0(ra)                       # return
verify_error_11:
    addi a0,zero,11
    jalr zero,0(ra)                       # return
verify_error_12:
    addi a0,zero,12
    jalr zero,0(ra)                       # return
verify_error_14:
    addi a0,zero,14
    jalr zero,0(ra)                       # return
verify_error_15:
    addi a0,zero,15
    jalr zero,0(ra)                       # return
